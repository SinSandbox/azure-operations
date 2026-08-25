// Parameter file for automation/bicep/main.bicep. Values are read from environment variables so
// the GitHub Actions workflow (.github/workflows/deploy-entra-pim-groups.yml) can inject the
// Demo Contributors/Demo Readers group object IDs produced by create-entra-groups.sh, and the
// target environment name, without editing this file per run.
//
// Local/manual usage:
//   export DEMO_CONTRIBUTORS_GROUP_OBJECT_ID="<object-id>"
//   export DEMO_READERS_GROUP_OBJECT_ID="<object-id>"
//   export ENVIRONMENT_NAME="dev"
//   az deployment sub create \
//     --location eastus \
//     --template-file automation/bicep/main.bicep \
//     --parameters automation/bicep/main.bicepparam
using 'main.bicep'

param demoContributorsGroupObjectId = readEnvironmentVariable('DEMO_CONTRIBUTORS_GROUP_OBJECT_ID')
param demoReadersGroupObjectId = readEnvironmentVariable('DEMO_READERS_GROUP_OBJECT_ID')
param environmentName = readEnvironmentVariable('ENVIRONMENT_NAME', 'dev')
