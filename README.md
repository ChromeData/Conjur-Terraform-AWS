# Lab 01 — Conjur Secrets into a Terraform/AWS Pipeline

**Terraform builds AWS infrastructure without an AWS credential ever touching
disk, shell history, or state. The obvious way to do this doesn't work — and
this lab proves that with a script instead of arguing about it.**

| | |
|---|---|
| **Domains** | CyberArk/Idira · AWS · Linux |
| **Built on** | [cyberark/conjur](https://github.com/cyberark/conjur) (LGPL-3.0) · [terraform-provider-conjur](https://github.com/cyberark/terraform-provider-conjur) (Apache-2.0) · [summon](https://github.com/cyberark/summon) (MIT) |
| **Cost** | < $1 (VPC + t3.micro) · **Runtime** ~4 hours |
| **Status** | 🟡 Built, not yet run |

---

## The problem

Standard Terraform-on-AWS leaks credentials in four places: `~/.aws/credentials`,
the shell environment, CI variables, and — the one everyone forgets —
**the state file, in plaintext**. Most teams fix three and ship the fourth.

## The trap

The obvious fix is the Conjur provider's `conjur_secret` data source. Pull the
credential from the vault at plan time, hand it to the AWS provider, done.

**It writes the credential into `terraform.tfstate` in plaintext.**

Terraform records *every* data source result in state — that's how it detects
drift — and it doesn't special-case secrets. The value never appeared as an
output. It was never a resource attribute. It's in state anyway.

So the obvious approach moves your credential out of one plaintext file and into
a different plaintext file, and it feels like a security improvement the whole
time. That's what makes it worth demonstrating.

## The fix

[Summon](https://github.com/cyberark/summon), CyberArk's own tool. It runs
Terraform as a child process with the secrets in its environment
([`summon/secrets.yml`](./summon/secrets.yml)). The AWS provider picks them up
through the normal credential chain. Terraform never holds a value it knows
about, so there's nothing for it to write down.

## Proving it

Both paths are wired up and switchable
([`terraform/credentials.tf`](./terraform/credentials.tf)):

```bash
make prove-leak
```

That builds it once with data sources, scans state, tears down, rebuilds with
Summon, scans again, and diffs the two reports. One command, measurable result.

[`scripts/verify-no-secrets-in-state.sh`](./scripts/verify-no-secrets-in-state.sh)
does the scanning — three checks:

1. **Access key IDs** by pattern (`AKIA`/`ASIA` + 16 chars).
2. **The secret key** by exact match against the live Conjur value — 40
   base64-ish characters matches far too much to catch by regex.
3. **Every `conjur_secret` in state**, with a plaintext character count. This is
   the check that explains the other two.

## Why a VPC and a bastion

Rather than an S3 bucket. The apply needs to run long enough to expose the
access-token TTL question, which is the interesting failure mode: Conjur tokens
are short-lived, and a long apply can outlive one.

The bastion is IMDSv2-only with an encrypted root volume, and `operator_cidr`
has **no default** with a validation rule rejecting `0.0.0.0/0` — a default
there eventually becomes open-to-the-world in someone's fork, which is the exact
class of mistake this lab is about.

## What I didn't build

Conjur, its Terraform provider, and Summon are CyberArk's. The credential-path
comparison, the state-scanning check, the switchable configuration, and the
infrastructure are mine.

---

## Running it

```bash
make up          # start Conjur
make policy      # load policy
make secrets     # store AWS credentials in the vault
make apply       # provision via Summon
make verify      # scan state — should pass
make prove-leak  # the demonstration
make clean       # tear it all down
```

Needs Docker, Terraform ≥ 1.9, `summon` + `summon-conjur`, `jq`.

## Findings

`findings/` fills in on the first run. [LAB-NOTES.md](./LAB-NOTES.md) is the log.

## License

Lab code: MIT ([LICENSE](./LICENSE)). Upstream tools keep their own licenses,
credited above.
