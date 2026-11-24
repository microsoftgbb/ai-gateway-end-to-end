#!/usr/bin/env bash
# After `az deployment sub create`: writes .vscode/mcp.json for GitHub Copilot in VS Code and
# prints the values for the Teams Developer Portal OAuth registration (Copilot connector).
set -euo pipefail

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-aigw-obo}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

output() {
  az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.outputs.$1.value" -o tsv
}

MCP_URL="$(output mcpEndpointUrl)"
mkdir -p "$ROOT/.vscode"
cat > "$ROOT/.vscode/mcp.json" <<EOF
{
  "inputs": [
    {
      "type": "promptString",
      "id": "ai-gateway-token",
      "description": "Azure AI Gateway token: az account get-access-token --scope https://ai.gateway.azure.com/Data.All --query accessToken -o tsv",
      "password": true
    }
  ],
  "servers": {
    "dummy-mcp": {
      "type": "http",
      "url": "$MCP_URL",
      "headers": {
        "Authorization": "Bearer \${input:ai-gateway-token}"
      }
    }
  }
}
EOF
echo "Wrote .vscode/mcp.json for $MCP_URL"
echo
echo "Copilot connector (Teams Developer Portal → OAuth client registration):"
az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.outputs.copilotConnector.value" -o yaml
echo "Create the client secret with: scripts/new-copilot-secret.sh"

STUDIO_CLIENT_ID="$(az deployment sub show --name "$DEPLOYMENT_NAME" \
  --query "properties.outputs.copilotStudio.value.clientId" -o tsv 2>/dev/null || true)"
if [[ -n "$STUDIO_CLIENT_ID" ]]; then
  echo
  echo "Copilot Studio (Tools → Add a tool → Model Context Protocol → OAuth 2.0 → Manual):"
  az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.outputs.copilotStudio.value" -o yaml
  echo "Create the client secret with: scripts/new-copilot-studio-secret.sh"
  echo "After saving the tool, add its Redirect URL to copilotStudioRedirectUris and redeploy."
fi
