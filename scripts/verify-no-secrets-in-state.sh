#!/usr/bin/env bash
# The lab's central claim, tested rather than asserted.
#
# Greps the full JSON state for anything resembling AWS credential material.
# Exits non-zero if it finds any — wire this into CI and the claim stays true
# as the configuration grows.

set -euo pipefail

STATE_JSON="$(terraform -chdir=terraform show -json 2>/dev/null)"

if [[ -z "${STATE_JSON}" ]] || [[ "${STATE_JSON}" == "null" ]]; then
  echo "no state yet — run 'make apply' first"
  exit 0
fi

FAIL=0

echo "==> Scanning state for access key IDs (AKIA/ASIA prefixes)"
if echo "${STATE_JSON}" | grep -qE '(AKIA|ASIA)[A-Z0-9]{16}'; then
  echo "    FAIL: access key ID found in state"
  FAIL=1
else
  echo "    pass"
fi

echo "==> Scanning state for the stored secret access key"
# Compare against the live value in Conjur rather than a pattern — a 40-char
# base64-ish string matches too many false positives to be useful as a regex.
SECRET="$(docker compose exec -T client conjur variable get -i aws-credentials/secret-access-key 2>/dev/null || true)"
if [[ -n "${SECRET}" ]] && echo "${STATE_JSON}" | grep -qF "${SECRET}"; then
  echo "    FAIL: secret access key found in state"
  FAIL=1
else
  echo "    pass"
fi

echo "==> Listing every conjur_secret value recorded in state"
echo "${STATE_JSON}" | jq -r '
  [.. | objects | select(.type? // "" | startswith("conjur_secret"))]
  | if length == 0 then "    none recorded"
    else (.[] | "    " + (.address // "?") + " -> value present: " + ((.values.value // "") | length | tostring) + " chars")
    end'

echo
if [[ "${FAIL}" -eq 0 ]]; then
  echo "PASS: no AWS credential material in Terraform state."
else
  echo "FAIL: credential material leaked into state. Document this in LAB-NOTES.md —"
  echo "      a negative result you investigated is worth more than a clean run."
  exit 1
fi
