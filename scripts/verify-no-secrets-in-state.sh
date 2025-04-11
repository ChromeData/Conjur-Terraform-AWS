#!/usr/bin/env bash
# The lab's central claim, tested rather than asserted.
#
# Scans Terraform state for AWS credential material and reports what it finds.
# Exit 0 = clean, exit 1 = leaked.
#
# Run it on both credential paths and the result is the whole lab:
#
#   credential_source = "summon"      -> clean
#   credential_source = "datasource"  -> leaks, every time
#
# Wire this into CI and the claim stays true as the configuration grows.

set -euo pipefail

cd "$(dirname "$0")/.."

STATE_JSON="$(terraform -chdir=terraform show -json 2>/dev/null || true)"

if [[ -z "${STATE_JSON}" ]] || [[ "${STATE_JSON}" == "null" ]]; then
  echo "no state yet - run 'make apply' first"
  exit 0
fi

FAIL=0
SOURCE="$(terraform -chdir=terraform output -raw credential_source 2>/dev/null || echo unknown)"
echo "==> credential_source = ${SOURCE}"
echo

# ---------------------------------------------------------------------------
# 1. Access key IDs are pattern-matchable. AKIA = long-lived, ASIA = STS.
# ---------------------------------------------------------------------------
echo "==> Scanning state for access key IDs (AKIA/ASIA)"
if echo "${STATE_JSON}" | grep -qE '(AKIA|ASIA)[A-Z0-9]{16}'; then
  echo "    FAIL: access key ID present in state"
  FAIL=1
else
  echo "    pass"
fi

# ---------------------------------------------------------------------------
# 2. The secret access key is 40 base64-ish characters, which matches far too
#    much to detect by pattern. Compare against the live value in Conjur instead.
# ---------------------------------------------------------------------------
echo "==> Scanning state for the secret access key (exact match against Conjur)"
SECRET="$(docker compose exec -T client conjur variable get -i aws-credentials/secret-access-key 2>/dev/null || true)"

if [[ -z "${SECRET}" ]]; then
  echo "    SKIP: could not read the value from Conjur (is the stack up?)"
elif echo "${STATE_JSON}" | grep -qF "${SECRET}"; then
  echo "    FAIL: secret access key present in state"
  FAIL=1
else
  echo "    pass"
fi

# ---------------------------------------------------------------------------
# 3. Enumerate any conjur_secret data source recorded in state.
#
#    This is the check that explains the other two. Terraform records every
#    data source result in state so it can detect drift - it does not
#    special-case secrets. On the datasource path the value is sitting here in
#    plaintext even though it was never an output and never a resource
#    attribute. That surprises people, which is exactly why it is worth
#    demonstrating.
# ---------------------------------------------------------------------------
echo "==> conjur_secret values recorded in state"
FOUND="$(echo "${STATE_JSON}" | jq -r '
  [.. | objects | select((.type? // "") | startswith("conjur_secret"))]
  | if length == 0 then
      "    none - no conjur_secret data source was read"
    else
      (.[] | "    " + (.address // "?") + " -> " +
        ((.values.value // "") | length | tostring) + " chars of plaintext")
    end')"
echo "${FOUND}"

if echo "${FOUND}" | grep -q "chars of plaintext"; then
  FAIL=1
fi

echo
if [[ "${FAIL}" -eq 0 ]]; then
  echo "PASS: no AWS credential material in Terraform state."
  echo "      Summon put the credentials in the process environment; Terraform"
  echo "      never held a value it could write down."
  exit 0
else
  echo "FAIL: credential material leaked into state."
  echo
  echo "      If credential_source = datasource, this is the expected result and"
  echo "      the point of the lab. Record the character counts in LAB-NOTES.md."
  echo "      If credential_source = summon, something is genuinely wrong."
  exit 1
fi
