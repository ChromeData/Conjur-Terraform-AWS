#!/usr/bin/env bash
# Load the Conjur policy tree in dependency order and capture the runner API key.
#
# The API key is returned exactly once, in the JSON response to the policy load
# that creates the host. There is no endpoint to retrieve it again — if you lose
# it you rotate the host. This script writes it to .conjur-runner-key and tells
# you loudly, because discovering that behaviour by accident is a bad afternoon.

set -euo pipefail

COMPOSE="docker compose"
ADMIN_KEY_FILE=".conjur-admin-key"
RUNNER_KEY_FILE=".conjur-runner-key"

if [[ ! -f "${ADMIN_KEY_FILE}" ]]; then
  echo "error: ${ADMIN_KEY_FILE} not found. Run 'make up' first." >&2
  exit 1
fi

# conjurctl prints a block of text; the API key is the last field on the line
# that mentions it. Parsing this is fragile by nature — pin the image tag.
ADMIN_API_KEY="$(grep -oE 'API key for admin: .*' "${ADMIN_KEY_FILE}" | awk '{print $NF}')"

if [[ -z "${ADMIN_API_KEY}" ]]; then
  echo "error: could not parse admin API key from ${ADMIN_KEY_FILE}" >&2
  echo "       inspect the file manually — the conjurctl output format may have changed" >&2
  exit 1
fi

echo "==> Authenticating as admin"
${COMPOSE} exec -T client conjur init --account lab --url http://conjur --self-signed 2>/dev/null || true
${COMPOSE} exec -T client conjur login -i admin -p "${ADMIN_API_KEY}"

echo "==> Loading root policy"
${COMPOSE} exec -T client conjur policy load -b root -f /policy/root.yml >/dev/null

echo "==> Loading aws-credentials policy"
${COMPOSE} exec -T client conjur policy load -b aws-credentials -f /policy/aws-credentials.yml >/dev/null

echo "==> Loading terraform-runner policy (this emits the host API key)"
LOAD_OUTPUT="$(${COMPOSE} exec -T client conjur policy load -b terraform-runner -f /policy/terraform-runner.yml)"

RUNNER_API_KEY="$(echo "${LOAD_OUTPUT}" | jq -r '.created_roles | to_entries[0].value.api_key // empty')"

if [[ -z "${RUNNER_API_KEY}" ]]; then
  echo
  echo "WARNING: no API key in the policy load response."
  echo "         This almost always means the host already existed. Conjur does not"
  echo "         re-emit keys on idempotent loads. To get a fresh one:"
  echo
  echo "           docker compose exec client conjur host rotate-api-key -i terraform-runner/pipeline"
  echo
  exit 1
fi

umask 077
echo "${RUNNER_API_KEY}" > "${RUNNER_KEY_FILE}"

cat <<EOF

  Runner API key written to ${RUNNER_KEY_FILE} (mode 600, gitignored).

  Export these before running terraform:

    export CONJUR_APPLIANCE_URL=http://localhost:8080
    export CONJUR_ACCOUNT=lab
    export CONJUR_AUTHN_LOGIN=host/terraform-runner/pipeline
    export CONJUR_AUTHN_API_KEY=\$(cat ${RUNNER_KEY_FILE})

  This key will not be shown again.

EOF
