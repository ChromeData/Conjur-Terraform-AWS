#!/usr/bin/env bash
# Populate the aws-credentials variables.
#
# Reads from your environment rather than prompting, so the values never land in
# shell history. Source them from a file you delete, or use `read -s`.
#
#   read -rs AWS_ACCESS_KEY_ID    && export AWS_ACCESS_KEY_ID
#   read -rs AWS_SECRET_ACCESS_KEY && export AWS_SECRET_ACCESS_KEY
#   export AWS_REGION=us-east-1
#   make secrets

set -euo pipefail

COMPOSE="docker compose"

: "${AWS_ACCESS_KEY_ID:?set AWS_ACCESS_KEY_ID (throwaway lab user only)}"
: "${AWS_SECRET_ACCESS_KEY:?set AWS_SECRET_ACCESS_KEY}"
: "${AWS_REGION:=us-east-1}"

# Sanity check: refuse to store a key that belongs to an account with too much
# power. This is a lab guardrail, not a security control, but getting in the
# habit of asserting scope before storing a credential is the right instinct.
echo "==> Verifying the key is scoped to a lab user"
CALLER_ARN="$(AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
              AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
              aws sts get-caller-identity --query Arn --output text)"

echo "    caller: ${CALLER_ARN}"

if [[ "${CALLER_ARN}" == *":root" ]]; then
  echo "error: that is a root credential. Absolutely not." >&2
  exit 1
fi

if [[ "${CALLER_ARN}" != *"conjur-lab-runner"* ]]; then
  read -rp "    ARN does not look like the lab user. Continue anyway? [y/N] " reply
  [[ "${reply}" == "y" ]] || exit 1
fi

echo "==> Storing in Conjur"
${COMPOSE} exec -T client conjur variable set -i aws-credentials/access-key-id     -v "${AWS_ACCESS_KEY_ID}"
${COMPOSE} exec -T client conjur variable set -i aws-credentials/secret-access-key -v "${AWS_SECRET_ACCESS_KEY}"
${COMPOSE} exec -T client conjur variable set -i aws-credentials/region            -v "${AWS_REGION}"

echo "==> Done. Now unset them from your shell:"
echo "    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY"
