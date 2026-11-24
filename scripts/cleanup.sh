#!/usr/bin/env bash
# Deletes what the Bicep deployment created: the resource group and the app registrations.
# Apps are deleted permanently so their uniqueName can be redeployed. Bicep deployments never delete
# Entra objects on their own. The AI Gateway Dataplane service principal is intentionally kept.
set -euo pipefail

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-aigw-obo}"

output() {
  az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.outputs.$1" -o tsv
}

RG="$(output resourceGroupName.value)"
APPS=(
  "$(output copilotConnector.value.clientId)"
  "$(output copilotStudio.value.clientId 2>/dev/null || true)"
  "$(output tokenExchangeAppClientId.value)"
  "$(output backendAppClientId.value)"
)

for app_id in "${APPS[@]}"; do
  [[ -n "$app_id" ]] || continue
  object_id="$(az ad app show --id "$app_id" --query id -o tsv 2>/dev/null || true)"
  [[ -n "$object_id" ]] || continue
  echo "Deleting app registration $app_id ..."
  az ad app delete --id "$app_id"
  purged=false
  for _ in $(seq 1 12); do
    if az rest --method DELETE --url "https://graph.microsoft.com/v1.0/directory/deletedItems/$object_id" \
      >/dev/null 2>&1; then
      purged=true
      break
    fi
    sleep 5
  done
  $purged || echo "Warning: $app_id is still in deleted items; redeploying the same namePrefix fails until it's permanently deleted." >&2
done

echo "Deleting resource group $RG ..."
az group delete --name "$RG" --yes
az deployment sub delete --name "$DEPLOYMENT_NAME"
echo "Done. Also remove the Teams Developer Portal OAuth registration, the M365 connector, and the Copilot Studio MCP tool."
