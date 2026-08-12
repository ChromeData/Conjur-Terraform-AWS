# Lab Notes, 01 Conjur → Terraform → AWS

Running log. Errors, dead ends, fixes, surprises. Dated, newest at the bottom.

---

## Format

```
### YYYY-MM-DD, what I was trying to do

**Expected:**
**Got:**
**Cause:**
**Fix:**
```

---

## The finding this lab exists for

The `conjur_secret` data source writes the retrieved value into
`terraform.tfstate` in plaintext.

This is not a bug in the provider. Terraform records every data source result in
state so it can detect drift, and it has no concept of "this result is
sensitive, don't persist it." Marking a variable `sensitive = true` only
suppresses *console output*. It does not keep the value out of state.

Consequence: the intuitive way to wire Conjur into Terraform moves the
credential from `~/.aws/credentials` to `terraform.tfstate`. Both are plaintext
files on disk. If state is in S3 without encryption, or in a repo, it is
arguably worse.

Summon avoids it because the secret only ever exists in the process environment.
Terraform receives no value it could record.

**Numbers to capture on the first run:** the exact character counts from
`make prove-leak` on both paths. Put both report files in `findings/`.

---

## Known traps (confirm when running)

### Conjur access-token TTL vs. a long apply

Conjur tokens are short-lived (8 minutes by default). A VPC + EC2 apply can run
longer than that. On the Summon path the credential is fetched once up front, so
this does not bite. On the data source path, a token expiring mid-apply produces
an auth error partway through, leaving half-built infrastructure. Worth
triggering deliberately and recording.

### `docker compose exec` in the verify script

Assumes the `client` service is up. If Conjur is down, check 2 skips rather than
fails, which could read as a pass. Confirm the SKIP path is obvious in output.

### Destroy on the datasource path

`make prove-leak` destroys with `-var credential_source=datasource` before
switching. Terraform needs the data sources to still resolve at destroy time. If Conjur is down, destroy fails and leaves AWS resources running. Check the
bill.

### State file removal between paths

`prove-leak` deletes `terraform.tfstate` between runs so the second scan is
clean rather than carrying the first run's history. Confirm no `.backup` file
survives with the old credential in it. That would be a false pass.

---

## Open questions

- [ ] Does `terraform.tfstate.backup` retain the leaked value after switching paths?
- [ ] Exact TTL before a mid-apply token expiry on the datasource path?
- [ ] Does the provider redact the value in `terraform show` output while still
      storing it in the file? (If so, that makes the leak even easier to miss.)
- [ ] Try short-lived STS credentials in Conjur instead of long-lived keys. Does that change the risk enough to make the datasource path acceptable?

---

## Log

### 2026-08-11, reading the provider docs, before running anything

The lab was originally written around the `conjur_secret` data source, with a comment
in `main.tf` asserting the value "is not persisted as managed state."

That comment was wrong, and I want to record why I believed it, because it's the whole
point of this lab.

The reasoning was: it's a data source, not a resource, and it's consumed directly by
the provider block, never surfaced as an output or a resource attribute. All true. And
none of it matters. Terraform records **every** data source result in state, because
that's how it detects drift on the next plan. It has no concept of "this result is
sensitive, don't write it down." Marking something `sensitive = true` suppresses
*console output* only.

So the intuitive Conjur-to-Terraform wiring takes the credential out of
`~/.aws/credentials` and puts it in `terraform.tfstate`. Both are plaintext files on
disk. If state lives in an unencrypted S3 bucket, or gets committed, it's arguably a
downgrade, and it feels like a security improvement the entire time.

**Restructured the lab around this.** Summon became the default path (secret lives in
the process environment, Terraform never holds a value it could record), the data
source became a switchable demo, and `verify-no-secrets-in-state.sh` became the thing
that settles it by measurement instead of argument.

**To confirm on the first run:** exact character counts from both paths, and whether
`terraform.tfstate.backup` retains the leaked value after switching. A stale backup
holding the credential would be a false pass.

---

### 2026-08-12, first real run: Conjur up, policy loaded, leak confirmed

Ran the stack for real against local Docker. Four things broke, all of them the
kind you only find by running it.

**1. The healthcheck never passes, and nothing tells you why.**

```
dependency failed to start: container 01-conjur-terraform-aws-conjur-1 is unhealthy
```

Conjur was fine. The healthcheck was hitting `/health`, which requires
authorization, so it answered 401 forever and the client container never
started. Checked every candidate endpoint:

```
GET /       -> 200
GET /info   -> 401
GET /health -> 401
GET /authn  -> 401
```

Root is the only usable unauthenticated readiness probe. Fixed in
docker-compose.yml. Worth knowing generally: a healthcheck pointed at an
authenticated endpoint fails closed and reports the *dependent* container as
the problem.

**2. `make up` never created the account.**

`load-policy.sh` expects `.conjur-admin-key`, which comes from
`conjurctl account create lab`. Nothing produced it. Added the step.

**3. Cross-branch grants cannot live in a branch policy.**

```
422 Unprocessable Content.
Variable 'terraform-runner/aws-credentials/access-key-id' not found in account 'lab'.
```

`terraform-runner.yml` is loaded with `-b terraform-runner`, so
`!variable aws-credentials/access-key-id` resolves *relative to that branch*.
Tried an absolute path and Conjur rejected that too:

```
422 Unprocessable Content. Illegal absolute id: /aws-credentials/access-key-id.
```

A grant spanning two branches has to be declared from a scope that can see
both, which means root. Moved it to `grants.yml`, loaded last with `-b root`.
That is also the better shape for review: "who can read the AWS credentials"
now has one answer in one file rather than being scattered across every
identity policy.

**4. Git Bash mangles container paths on Windows.**

```
Error: open C:/Program Files/Git/policy/root.yml: no such file or directory
```

MSYS rewrites `/policy/root.yml` into a Windows path before Docker sees it.
`MSYS_NO_PATHCONV=1` fixes it. Linux and macOS are unaffected.

**Then the actual experiment.**

Built a minimal config in `experiments/state-leak/`: three `conjur_secret` data
sources plus one `terraform_data` resource. No AWS provider, no AWS resources,
and nothing referencing the secrets. Anything appearing in state therefore came
from the data source itself.

```
occurrences of the access key id in terraform.tfstate: 1
occurrences of the secret access key in terraform.tfstate: 1

conjur_secret.access_key_id      value stored: true  length: 20
conjur_secret.region             value stored: true  length: 9
conjur_secret.secret_access_key  value stored: true  length: 40
```

**Confirmed.** All three credentials sit in `terraform.tfstate` in plaintext,
including the full 40-character secret key. Never an output, never a resource
attribute, still written to disk.

This is the claim the whole lab rests on and it is now measured rather than
argued. Full output in `findings/state-leak-experiment.txt`. Values used were
AWS's published example credentials, not live keys.

---

### 2026-08-12, validate + fmt in CI

`terraform validate` passes on both credential paths. Added `fmt -check` to CI after
`fmt` reformatted `rotation.tf` locally, if formatting drifts, I'd rather CI say so
than discover it in a diff.
