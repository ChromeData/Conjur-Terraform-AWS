# Lab 01: Conjur Secrets into a Terraform/AWS Pipeline

[![tests](https://github.com/ChromeData/Conjur-Terraform-AWS/actions/workflows/tests.yml/badge.svg)](https://github.com/ChromeData/Conjur-Terraform-AWS/actions/workflows/tests.yml)

**Terraform builds AWS infrastructure without an AWS key ever touching disk, shell history, or state. The obvious way to do this quietly fails, and this lab proves it with a script.**

| | |
|---|---|
| **Domains** | CyberArk/Idira, AWS, Linux |
| **Built on** | [cyberark/conjur](https://github.com/cyberark/conjur), [terraform-provider-conjur](https://github.com/cyberark/terraform-provider-conjur), [summon](https://github.com/cyberark/summon) |
| **Cost** | Under $1. **Runtime** ~4 hours |
| **Status** | Run for real. Conjur stack up, policy loaded, state leak confirmed and measured (output in findings/). AWS provisioning still pending |

## Situation

Standard Terraform on AWS leaks credentials in four places: the local AWS file, the shell environment, CI variables, and the one everyone forgets, the state file, in plain text. Most teams fix three and ship the fourth.

## Task

Pull the AWS credential from the Conjur vault and hand it to Terraform so that no copy of it lands on disk or in state.

## Action

The obvious fix is the Conjur provider's secret data source. I wired that up, then found it writes the credential straight into `terraform.tfstate` in plain text. Terraform records every data source result so it can spot drift, and it does not treat secrets differently. So that approach just moves the credential from one plain text file to another.

The real fix is Summon, CyberArk's own tool. It runs Terraform with the secret in the process environment. Terraform never holds a value it can write down.

I built both paths, made them switchable, and wrote a scanner that reads the state and looks for AWS credential material.

## Result

**Confirmed by measurement, not argument.** I ran the stack against local Docker and applied a minimal config in [experiments/state-leak](./experiments/state-leak) with three Conjur data sources, no AWS provider, and nothing referencing the secrets. All three credentials landed in `terraform.tfstate` in plaintext, including the full 40 character secret key:

```
conjur_secret.access_key_id      value stored: true  length: 20
conjur_secret.secret_access_key  value stored: true  length: 40
```

Full output in [findings/state-leak-experiment.txt](./findings/state-leak-experiment.txt). Values used were AWS's published example credentials, not live keys.

The run also exposed four real bugs: a healthcheck pointed at an authenticated endpoint that hung the whole stack, a missing account creation step, a cross branch Conjur grant that cannot be declared inside a branch policy, and Git Bash rewriting container paths on Windows. All four are fixed and written up in [LAB-NOTES.md](./LAB-NOTES.md).

## What I did not build

Conjur, its provider, and Summon are CyberArk's. The two paths, the scanner, the switch, and the infrastructure are mine.

## Run it

```bash
make up          # start Conjur
make policy      # load policy
make secrets     # store AWS credentials in the vault
make apply       # provision via Summon
make verify      # scan state, should pass
make prove-leak  # the demonstration
make clean       # tear down
```

Needs Docker, Terraform 1.9+, summon, jq.

## Findings

`findings/` fills in on the first run. [LAB-NOTES.md](./LAB-NOTES.md) is the running log.

## License

Lab code: MIT ([LICENSE](./LICENSE)). Upstream tools keep their own licenses, credited above.
