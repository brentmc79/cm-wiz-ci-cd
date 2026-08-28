#!/usr/bin/env bash
set -eo pipefail

echo "=========================================================="
echo " Starting Google CodeMender Fix Runner in Cloud Run"
echo " Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=========================================================="

# Check for required GITHUB_TOKEN
if [[ -z "${GITHUB_TOKEN}" ]]; then
  echo "[-] ERROR: GITHUB_TOKEN is missing or empty." >&2
  exit 1
fi

# Execute the orchestrator
exec python3 /app/fix_orchestrator.py "$@"
