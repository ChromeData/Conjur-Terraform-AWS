# Lab 01 — Conjur Secrets Injection into a Terraform/AWS Pipeline

**Terraform provisions AWS infrastructure without any AWS credential ever touching
disk, environment history, or state — it authenticates to Conjur as a machine
identity and retrieves short-lived secrets at plan time.**

| | |
|---|---|
| **Domains** | CyberArk/Idira · Linux · AWS |
| **Built on** | [cyberark/conjur](https://github.com/cyberark/conjur) (LGPL-3.0) · [cyberark/terraform-provider-conjur](https://github.com/cyberark/terraform-provider-conjur) (Apache-2.0) |
| **Runtime** | ~4 hours · < $1 in AWS spend (VPC + t3.micro) |
| **Status** | 🟡 In progress |

---

## Why this lab exists

The standard Terraform-on-AWS pattern leaks credentials in at least four places:
`~/.aws/credentials`, the shell environment, CI variables, and — the one people
forget — **the state file, in plaintext**. Every `aws_iam_access_key` resource
writes its secret into `terraform.tfstate`. Most teams solve three of these four
and quietly ship the fourth.

Conjur's Terraform provider has 24 stars and no published end-to-end example.
The docs cover authentication and the docs cover secret retrieval, but nobody has
put the whole loop together against real AWS resources and written down where it
falls apart. That gap is the lab.

## What I built

- A local Conjur OSS deployment (Docker Compose: Postgres + Conjur server) with
  a real data key and an initialised `lab` account.
- A **Conjur policy tree** modelling a realistic separation: a `terraform-runner`
  host identity, an `aws-credentials` variable group, and a permission grant that
  is deliberately least-privilege — the runner can `execute` the secrets it needs
  and nothing else.
- A **Terraform configuration** that reads AWS credentials from Conjur at plan
  time via `data.conjur_secret`, provisions a VPC and a bastion, and never
  materialises a credential in state.
- A **bootstrap script** that loads policy, rotates the variable values, and emits
  the host API key exactly once.

## What I did not build

Conjur itself, the Terraform provider, and the Conjur Docker images are CyberArk's
work. This lab is the policy model, the Terraform integration, the automation
around them, and the analysis of where the pattern breaks.

---

## Architecture

```
┌──────────────┐   1. authn (host identity + API key)
│  Terraform   │ ─────────────────────────────────────►┌──────────────┐
│   runner     │                                        │    Conjur    │
│              │◄───────────────────────────────────── │   OSS 1.24   │
└──────┬───────┘   2. short-lived access token          └──────┬───────┘
       │                                                        │
       │           3. data.conjur_secret.aws_*                  │
       │◄───────────────────────────────────────────────────────┘
       │
       │           4. provider "aws" { access_key = <from step 3> }
       ▼
┌──────────────┐
│     AWS      │  VPC · subnets · SG · bastion
└──────────────┘
```

The critical property: step 3 returns a value that Terraform holds **in memory
only**. It is marked sensitive and never written to state, because it is consumed
as provider configuration rather than stored as a resource attribute.

---

## Running it

### Prerequisites

```bash
terraform  >= 1.9.0
docker     >= 24.0    # with compose v2
aws-cli    >= 2.15    # for verifying what actually got created
jq         >= 1.7
```

### Setup

```bash
make up            # brings up Conjur, initialises the lab account
make policy        # loads conjur/policy/*.yml, prints the host API key ONCE
make secrets       # populates aws-credentials/* — see note below
make plan          # terraform plan, credentials pulled from Conjur
make apply
```

`make secrets` expects real AWS keys for a **throwaway IAM user** scoped to the
`terraform-lab` permission boundary. Create it first:

```bash
aws iam create-user --user-name conjur-lab-runner
aws iam put-user-policy --user-name conjur-lab-runner \
  --policy-name lab-boundary --policy-document file://docs/iam-boundary.json
```

### Teardown

```bash
make destroy       # terraform destroy, then docker compose down -v
```

> `-v` matters. Leaving the Conjur Postgres volume behind means the next `make up`
> silently reuses the old data key and the account init fails in a way that is
> genuinely confusing. See LAB-NOTES 2026-XX-XX.

---

## Verifying the claim

The whole point is "no credential in state." Prove it rather than asserting it:

```bash
make verify
```

Which runs:

```bash
# should return nothing
terraform show -json | jq -r '.. | strings' | grep -E 'AKIA|aws_secret' || echo "PASS: no credentials in state"
```

---

## Findings

Fill this in as you go. Suggested shape:

| Finding | Severity | Evidence |
|---------|----------|----------|
| | | |

Questions worth answering here:
- Does the Conjur access token TTL (default 8 min) survive a long `terraform apply`?
- What happens to the pipeline when Conjur is unreachable mid-apply?
- Does `terraform refresh` re-authenticate, or reuse a cached token?

## What broke

See [LAB-NOTES.md](./LAB-NOTES.md).

## What I would do differently

Written at the end.
