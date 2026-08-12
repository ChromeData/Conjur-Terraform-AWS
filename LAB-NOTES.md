# Lab Notes — Conjur + Terraform + AWS

> Running log, newest first. Write entries as you hit them.

---

## Known traps (pre-seeded — confirm or delete once you hit them)

These are the failure modes this lab is designed to surface. Replace each with
what actually happened on your run, including the real error text.

### Stale Postgres volume after `docker compose down`

Without `-v`, the Conjur database survives. `conjurctl account create lab` then
fails against a database initialised with a different `CONJUR_DATA_KEY`, and the
error does not obviously point at the volume. `make destroy` uses `-v` for
exactly this reason.

### The runner API key is emitted once

Policy load returns `created_roles` with the API key. Reload the same policy and
Conjur treats it as idempotent — no new key, no warning that you just lost it.
Recovery is rotation, not retrieval:

```bash
docker compose exec client conjur host rotate-api-key -i terraform-runner/pipeline
```

### Access token TTL vs. long applies

Conjur access tokens default to roughly 8 minutes. Worth measuring: does a
`terraform apply` that runs longer than the TTL fail, or does the provider
re-authenticate transparently? Test it by adding an artificial delay
(`time_sleep` resource) and record the result — this is the finding most worth
publishing, because the docs do not answer it.

### `sensitive = true` is not encryption

If you expose a Conjur value as an output — even marked sensitive — it is written
to state in plaintext. Try it deliberately once, run `make verify`, watch it fail,
then remove it. A demonstrated failure is better evidence than a passing test.

---

## YYYY-MM-DD — <first real entry goes here>

**Goal:**

**What happened:**

```
```

**Why:**

**Fix:**

**Time lost:**

---

## Open questions

- [ ] Does the provider re-authenticate mid-apply, or hold one token?
- [ ] What is the blast radius if Conjur is unreachable during `terraform destroy`?
- [ ] Is there a clean pattern for rotating `aws-credentials/*` without a re-plan?

## What I would do differently

_Written at the end._
