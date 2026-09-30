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
terraform plan -input=false -lock-timeout=10m -var-file="$VARFILE" -out=tfplan
terraform show -no-color tfplan > plan.txt
echo "plan written to $(pwd)/plan.txt"
