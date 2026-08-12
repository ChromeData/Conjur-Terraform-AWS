# Lab Notes — 01 Conjur → Terraform → AWS

Running log. Errors, dead ends, fixes, surprises. Dated, newest at the bottom.

---

## Format

```
### YYYY-MM-DD — what I was trying to do

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
suppresses *console output* — it does not keep the value out of state.

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
an auth error partway through — leaving half-built infrastructure. Worth
triggering deliberately and recording.

### `docker compose exec` in the verify script

Assumes the `client` service is up. If Conjur is down, check 2 skips rather than
fails, which could read as a pass. Confirm the SKIP path is obvious in output.

### Destroy on the datasource path

`make prove-leak` destroys with `-var credential_source=datasource` before
switching. Terraform needs the data sources to still resolve at destroy time —
if Conjur is down, destroy fails and leaves AWS resources running. Check the
bill.

### State file removal between paths

`prove-leak` deletes `terraform.tfstate` between runs so the second scan is
clean rather than carrying the first run's history. Confirm no `.backup` file
survives with the old credential in it — that would be a false pass.

---

## Open questions

- [ ] Does `terraform.tfstate.backup` retain the leaked value after switching paths?
- [ ] Exact TTL before a mid-apply token expiry on the datasource path?
- [ ] Does the provider redact the value in `terraform show` output while still
      storing it in the file? (If so, that makes the leak even easier to miss.)
- [ ] Try short-lived STS credentials in Conjur instead of long-lived keys —
      does that change the risk enough to make the datasource path acceptable?

---

## Log

_(first entry goes here on the first real run)_
