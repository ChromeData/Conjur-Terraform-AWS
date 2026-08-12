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

### 2026-08-12, validate + fmt in CI

`terraform validate` passes on both credential paths. Added `fmt -check` to CI after
`fmt` reformatted `rotation.tf` locally, if formatting drifts, I'd rather CI say so
than discover it in a diff.
