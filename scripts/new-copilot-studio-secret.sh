#!/usr/bin/env bash
# Adds a client secret to the Copilot Studio client app (App D) for the MCP tool's OAuth 2.0
# (Manual) settings. The Microsoft Graph Bicep extension can't create secrets, so this is a
# separate, explicit step. The secret is printed once; paste it into Copilot Studio only.
set -euo pipefail

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-aigw-obo}"
APP_ID="$(az deployment sub show --name "$DEPLOYMENT_NAME" \
  --query "properties.outputs.copilotStudio.value.clientId" -o tsv)"

if [[ -z "$APP_ID" ]]; then
  echo "No Copilot Studio client app in deployment '$DEPLOYMENT_NAME' (enableCopilotStudioClient = false?)." >&2
  exit 1
fi

az ad app credential reset --id "$APP_ID" --append --display-name "copilot-studio-mcp-oauth" \
  --years 1 --query password -o tsv
