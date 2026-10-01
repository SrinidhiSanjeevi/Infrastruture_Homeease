#!/usr/bin/env bash
# Usage: terraform-plan.sh <environment-dir> <var-file>
# Runs inside the AzureCLI task, so `az` is already logged in.
set -euo pipefail

ENV_DIR="$1"
VARFILE="$2"

echo "environment dir : $ENV_DIR"
echo "var file        : $VARFILE"

[ -d "$ENV_DIR" ]  || { echo "ERROR: environment dir not found: $ENV_DIR" >&2; exit 2; }
[ -f "$VARFILE" ]  || { echo "ERROR: var file not found: $VARFILE" >&2; exit 2; }

cd "$ENV_DIR"
terraform version

ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export ARM_SUBSCRIPTION_ID

terraform init -input=false -reconfigure
# PLAN_LOCK=false when running with the read-only identity (no state lease).
terraform plan -input=false -lock="${PLAN_LOCK:-true}" -lock-timeout=10m -var-file="$VARFILE" -out=tfplan
# Show in the log only (sensitive values stay masked). No plan.txt file is
# written, so nothing readable ends up in the downloadable artifact.
terraform show -no-color tfplan | tee "${AGENT_TEMPDIRECTORY:-/tmp}/plan.txt"

# Put the plan on the run's Summary tab so approvers can read it there.
# Kept in the agent temp dir (not the artifact). Sensitive values are masked by terraform.
SUMMARY="${AGENT_TEMPDIRECTORY:-/tmp}/plan-summary.md"
{
  echo "## Terraform plan: $(basename "$ENV_DIR")"
  echo
  echo "**$(grep -E '^(Plan:|No changes)' "${AGENT_TEMPDIRECTORY:-/tmp}/plan.txt" | head -1)**"
  echo
  echo '```'
  head -n 400 "${AGENT_TEMPDIRECTORY:-/tmp}/plan.txt"
  echo '```'
} > "$SUMMARY"
echo "##vso[task.uploadsummary]$SUMMARY"
