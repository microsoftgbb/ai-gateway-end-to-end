using 'main.bicep'

param location = 'swedencentral'
param namePrefix = 'aigwobo'

// Extra users or groups (object IDs) allowed to call the MCP server through the gateway,
// e.g. the group of people who use the Copilot connector.
// param runtimeAccessPrincipalIds = ['11111111-1111-1111-1111-111111111111']

// Redirect URLs Copilot Studio generates when you save the MCP tool (one per tool), then redeploy.
// param copilotStudioRedirectUris = ['https://global.consent.azure-apim.net/redirect/<generated>']

// Build the MCP server image from your fork or branch instead.
// param mcpServerSource = 'https://github.com/<you>/ai-gateway-end-to-end.git#main:mcp-server'
