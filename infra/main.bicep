// M365 Copilot / Copilot Cowork -> Azure AI Gateway -> MCP server, as the signed-in user.
// Entra objects use the Microsoft Graph Bicep extension; Azure resources use ARM.
//
// az deployment sub create --name aigw-obo --location swedencentral \
//   --template-file infra/main.bicep --parameters infra/main.bicepparam
targetScope = 'subscription'

@description('Azure region for all resources. Must be a region where Azure AI Gateway is available.')
@allowed([
  'australiaeast'
  'canadaeast'
  'centralus'
  'eastus'
  'eastus2'
  'francecentral'
  'japaneast'
  'northcentralus'
  'northeurope'
  'southcentralus'
  'southeastasia'
  'swedencentral'
  'uksouth'
  'westeurope'
  'westus'
  'westus2'
])
param location string = 'swedencentral'

@description('Prefix for resource and app registration names. A deterministic suffix is appended.')
@minLength(3)
@maxLength(12)
param namePrefix string = 'aigwobo'

@description('Extra tags applied to Azure resources.')
param tags object = {}

@description('Name of the AI Gateway MCP server. It becomes part of the gateway MCP endpoint URL.')
param mcpServerName string = 'dummy-mcp'

@description('Namespace prefixed to the backend\'s tool names on the gateway (<namespace>_<tool>).')
param mcpToolNamespace string = 'dummy'

@description('MCP protocol versions the gateway advertises. Only list versions the backend supports; M365 Copilot proposes 2025-11-25.')
param mcpProtocolVersions array = [
  '2025-11-25'
  '2025-06-18'
  '2025-03-26'
]

@description('Delegated scope exposed by the MCP backend app registration and requested by the gateway during OBO.')
param backendScopeName string = 'user_impersonation'

@description('Minimum MCP backend replicas. Keep 1 to avoid cold starts during Copilot tool discovery.')
param mcpMinReplicas int = 1

@description('Enable Container Apps built-in authentication (Easy Auth) with the backend app registration.')
param enableEasyAuth bool = true

@description('Create the Entra client app used by the Microsoft 365 Copilot / Copilot Cowork federated connector.')
param enableCopilotConnector bool = true

@description('Create the Entra client app used by a Copilot Studio agent (MCP tool, OAuth 2.0 Manual).')
param enableCopilotStudioClient bool = true

@description('Redirect URLs that Copilot Studio generates when you save the MCP tool. Add each one and redeploy.')
param copilotStudioRedirectUris array = []

@description('Assign "AI Gateway Tools User" on the MCP server to the identity running the deployment.')
param grantRuntimeAccessToDeployer bool = true

@description('Object IDs of additional users or groups that may invoke the MCP server through the gateway.')
param runtimeAccessPrincipalIds array = []

@description('Git build context for the MCP server image (ACR Tasks): <repo>.git#<branch>:<folder>.')
param mcpServerSource string = 'https://github.com/kostapetan/ai-gateway-end-to-end.git#main:mcp-server'

@description('Image tag. The default rebuilds the image from mcpServerSource on every deployment.')
param mcpImageTag string = utcNow('yyyyMMddHHmmss')

var suffix = take(uniqueString(subscription().id, namePrefix, location), 5)
var baseName = '${namePrefix}-${suffix}'
var allTags = union({ workload: 'ai-gateway-obo-mcp' }, tags)
var deployerObjectId = deployer().objectId
var runtimePrincipalIds = union(grantRuntimeAccessToDeployer ? [deployerObjectId] : [], runtimeAccessPrincipalIds)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${baseName}'
  location: location
  tags: allTags
}

module identities 'modules/identities.bicep' = {
  scope: rg
  params: {
    baseName: baseName
    location: location
    tags: allTags
  }
}

module entra 'modules/entra.bicep' = {
  scope: rg
  params: {
    baseName: baseName
    gatewayIdentityPrincipalId: identities.outputs.gatewayPrincipalId
    backendScopeName: backendScopeName
    enableCopilotConnector: enableCopilotConnector
    enableCopilotStudioClient: enableCopilotStudioClient
    copilotStudioRedirectUris: copilotStudioRedirectUris
    ownerObjectId: deployerObjectId
  }
}

module mcpServer 'modules/mcp-server.bicep' = {
  scope: rg
  params: {
    baseName: baseName
    location: location
    tags: allTags
    identityId: identities.outputs.mcpAppIdentityId
    identityPrincipalId: identities.outputs.mcpAppPrincipalId
    backendAppId: entra.outputs.backendAppId
    tokenExchangeAppId: entra.outputs.tokenExchangeAppId
    backendScopeName: backendScopeName
    minReplicas: mcpMinReplicas
    enableEasyAuth: enableEasyAuth
    sourceLocation: mcpServerSource
    imageTag: mcpImageTag
  }
}

module aiGateway 'modules/ai-gateway.bicep' = {
  scope: rg
  params: {
    baseName: baseName
    location: location
    tags: allTags
    identityId: identities.outputs.gatewayIdentityId
    identityClientId: identities.outputs.gatewayClientId
    tokenExchangeAppId: entra.outputs.tokenExchangeAppId
    backendScope: entra.outputs.backendScope
    mcpBackendUrl: mcpServer.outputs.mcpUrl
    mcpServerName: mcpServerName
    mcpToolNamespace: mcpToolNamespace
    mcpProtocolVersions: mcpProtocolVersions
    runtimePrincipalIds: runtimePrincipalIds
  }
}

var authority = '${environment().authentication.loginEndpoint}${tenant().tenantId}'

output tenantId string = tenant().tenantId
output resourceGroupName string = rg.name
output aiGatewayName string = aiGateway.outputs.name
output aiGatewayHostname string = aiGateway.outputs.hostname
@description('Gateway MCP endpoint: the connector Base URL (Copilot) or MCP server URL (VS Code).')
output mcpEndpointUrl string = aiGateway.outputs.mcpEndpointUrl
@description('Container App MCP endpoint. Rejects any token that didn\'t come through the gateway OBO exchange.')
output mcpBackendUrl string = mcpServer.outputs.mcpUrl
output backendAppClientId string = entra.outputs.backendAppId
output backendScope string = entra.outputs.backendScope
output tokenExchangeAppClientId string = entra.outputs.tokenExchangeAppId
output gatewayManagedIdentity object = {
  resourceId: identities.outputs.gatewayIdentityId
  clientId: identities.outputs.gatewayClientId
  principalId: identities.outputs.gatewayPrincipalId
}
@description('Values for the Teams Developer Portal OAuth client registration and the M365 federated connector.')
output copilotConnector object = enableCopilotConnector
  ? {
      clientId: entra.outputs.copilotConnectorAppId
      clientSecret: 'run scripts/new-copilot-secret.sh'
      baseUrl: aiGateway.outputs.mcpEndpointUrl
      authorizationEndpoint: '${authority}/oauth2/v2.0/authorize'
      tokenEndpoint: '${authority}/oauth2/v2.0/token'
      refreshEndpoint: '${authority}/oauth2/v2.0/token'
      scopes: 'https://ai.gateway.azure.com/Data.All offline_access'
      pkce: 'Enabled'
      restrictUsageByOrg: 'My organization only'
      restrictUsageByApp: 'Any Teams app'
      redirectUri: entra.outputs.copilotConnectorRedirectUri
    }
  : {}
@description('Values for the Copilot Studio MCP tool (Tools → Add a tool → Model Context Protocol → OAuth 2.0 → Manual).')
output copilotStudio object = enableCopilotStudioClient
  ? {
      clientId: entra.outputs.copilotStudioAppId
      clientSecret: 'run scripts/new-copilot-studio-secret.sh'
      serverUrl: aiGateway.outputs.mcpEndpointUrl
      authorizationUrl: '${authority}/oauth2/v2.0/authorize'
      tokenUrlTemplate: '${authority}/oauth2/v2.0/token'
      refreshUrl: '${authority}/oauth2/v2.0/token'
      scopes: 'https://ai.gateway.azure.com/Data.All offline_access'
      redirectUris: copilotStudioRedirectUris
    }
  : {}
