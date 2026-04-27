# Learn Azure Function

### Prerequisite

- UV and Python 3.13
- VS Code with extensions: `Azure Functions`, `Azure Resources`, and `Azurite`
- Azure CLI
- Azure Account

### Steps

- Clone this project.
- Create virtual environment, run `uv venv`.
- Install packages, run `uv pip install -r requirements.txt`.
- Start Azurite services (Blob, Queue, Table):
  - Press `Cmd + Shift + P` (or `Ctrl + Shift + P`)
  - Type `Azurite: Start` then press `Enter`
- Press `F5` to start and run the azure function locally

### Try

**Local**

```sh
curl -X POST http://localhost:7071/api/json_payload \
  -H "Content-Type: application/json" \
  -d '{
    "event": "pet_weight_check",
    "pet": {
      "id": "P-0001",
      "name": "Chubby"
    },
    "observation": {
      "note": "Healthy",
      "unit": "g",
      "weight": 82.4,
      "weight_at": "2026-04-24T09:32:19Z"
    },
    "staff": {
      "id": "S-0089",
      "name": "Game"
    }
  }'
```

**Live**

```sh
curl -i -X POST "https://<YOUR_APP_NAME>.azurewebsites.net/api/json_payload?code=<YOUR_FUNCTION_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "pet_weight_check",
    "pet": { "id": "P-CLOUD-01" },
    "observation": {
      "weight": 52.2,
      "weight_at": "2026-04-24T10:15:00Z",
      "note": "Testing live"
    },
    "staff": { "id": "S-007" }
  }'
```

### Local Development Workflow Diagram

```mermaid
graph LR
    subgraph "Your Machine (Local)"
        A[function_app.py] -- Triggers/Bindings --> B(Azurite Emulator)
        B --> C[(Local Folders)]
        C --- C1["__blobstorage__"]
        C --- C2["__queuestorage__"]
    end

    subgraph "VS Code Tools"
        D[Azure Functions Core Tools] -- Runs --> A
    end
```

### Project Structure

```txt
/
├── __blobstorage__/      # Local Azure Blob Storage (Azurite data)
├── __queuestorage__/     # Local Azure Queue Storage (Azurite data)
├── __azurite_db_*.json   # Azurite metadata and internal state
├── .venv/                # Python virtual environment
├── host.json             # Global configuration for Azure Functions
├── local.settings.json   # Local environment variables & secrets (Excluded from Git)
├── requirements.txt      # Project dependencies (e.g., azure-functions)
└── function_app.py       # Main Entry Point: Azure Functions V2 programming model
```

---

### Azure CLI exmaples

**Login via CLI**

```sh
az login
```

**Create Resource Group**

```sh
az group create --name rg-learn-webhook --location southeastasia
```

**Delete Resource Group**

```sh
az group delete --name rg-learn-webhook
```

**Create a Storage Account (Real version of Azurite)**

_Note: `--name` must be globally unique, lowercase, no symbols._

```sh
az storage account create \
  --name gamelearnwebhook \
  --location southeastasia \
  --resource-group rg-learn-webhook \
  --sku Standard_LRS
```

**Create the Function App**

```sh
az functionapp create \
  --name game-learn-webhook \
  --resource-group rg-learn-webhook \
  --storage-account gamelearnwebhook \
  --flexconsumption-location southeastasia \
  --runtime python \
  --runtime-version 3.13 \
  --instance-memory 2048
```

**Delete the Function App**

```sh
az functionapp delete \
  --name func-learn-game \
  --resource-group rg-learn-webhook
```

**List the Function App Service Plan**

```sh
az functionapp plan list \
  --resource-group rg-learn-webhook \
  --output table
```

**Delete the Function App Service Plan**

```sh
az functionapp plan delete \
  --name <YOUR_PLAN_NAME> \
  --resource-group rg-learn-webhook \
  --yes
```

**Deploy the Function App**

```sh
func azure functionapp \
  publish game-learn-webhook \
  --build remote
```

**Stream the Function App Logs**

```sh
func azure functionapp \
  logstream game-learn-webhook
```

**Set the Function App Environment Variables**

```sh
az functionapp config appsettings set \
  --name game-learn-webhook
  --resource-group rg-learn-webhook
  --settings MY_API_KEY=12345
```

**Get the Host Key (Recommended)**

```sh
az functionapp keys list \
  --name game-learn-webhook \
  --resource-group rg-learn-webhook \
  --query "functionKeys.default" \
  --output tsv
```

**Get a Specific Function Key**

```sh
az functionapp function keys list \
  --function-name json_payload \
  --name game-learn-webhook \
  --resource-group rg-learn-webhook \
  --query "default" \
  --output tsv
```

**Get a master key (Full Admin, Careful with this!)**

```sh
az functionapp keys list --query masterKey
```

---

### Cosmos DB

0. **Register the Cosmos DB provider** [OPTIONAL]

   ```sh
   az provider register --namespace Microsoft.DocumentDB
   ```

   Note: Registration can take 1–2 minutes. You can check the status with:

   ```sh
   az provider show -n Microsoft.DocumentDB --query registrationState
   ```

1. Create the Cosmos DB Account

   ```sh
   az cosmosdb create \
     --name db-learn-webhook \
     --resource-group rg-learn-webhook \
     --locations regionName="Southeast Asia" failoverPriority=0 isZoneRedundant=False \
     --capabilities EnableServerless
   ```

   Note: Cosmos DB provisioning usually takes 5–10 minutes, you can check the progress with this command:

   ```sh
   az cosmosdb show \
     --name db-learn-webhook \
     --resource-group rg-learn-webhook \
     --query "provisioningState"
   ```

2. Create the Database

   ```sh
   az cosmosdb sql database create \
     --name ObservationLog \
     --account-name db-learn-webhook \
     --resource-group rg-learn-webhook
   ```

3. Create the Container with /pet/id as the Partition Key. This ensures all records for the same pet stay on the same physical partition for speed.

   ```sh
   az cosmosdb sql container create \
     --name ObservationContainer \
     --account-name db-learn-webhook \
     --resource-group rg-learn-webhook \
     --database-name ObservationLog \
     --partition-key-path "/pet/id"
   ```

4. Get the connection string:

   ```sh
   az cosmosdb keys list \
     --name db-learn-webhook \
     --resource-group rg-learn-webhook \
     --type connection-strings \
     --query "connectionStrings[0].connectionString" \
     -o tsv
   ```

5. Add it to local.settings.json:

   ```json
   {
     "IsEncrypted": false,
     "Values": {
       "AzureWebJobsStorage": "UseDevelopmentStorage=true",
       "CosmosDbConnectionString": "<PASTE_YOUR_CONNECTION_STRING_HERE>",
       "FUNCTIONS_WORKER_RUNTIME": "python"
     }
   }
   ```

---

### Storage Queues (The Simple Route)

**Create the Queue**

```sh
az storage queue create \
  --name learn-webhook-queue \
  --account-name db-learn-webhook
```

### GitHub Actions Setup with OIDC (OpenID Connect)

- Create a Workflow File: `.github/workflows/deploy.yml`
- Get Subscription ID

  ```sh
  az account show --query id -o tsv
  ```

- Create a Service Principal with "Contributor" role to GitHub

  ```sh
  az ad sp create-for-rbac \
    --name "github-actions-game" \
    --role contributor \
    --scopes /subscriptions/<SUB_ID>/resourceGroups/rg-learn-webhook \
    --json-auth
  ```

- Copy the JSON output.
- Go to your Repo > **Settings** > **Secrets and variables** > **Actions** > **New repository secret**.
- Enter `AZURE_CREDENTIALS` to the Name and paste the JSON to the Secret.

---

### Definitions

| Keyword        | Description                                                                                                                                                                                                                                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Resource Group | a 'bucket' or 'folder' used to collect all the services you create—such as Databases, Functions, and Storage—into one place for easy management.                                                                                                                                                                   |
| Azurite        | A Cloud Emulator (simulates the cloud on your local machine). Instead of having to stay connected to the internet to use actual Azure Storage, Azurite simulates Blob, Queue, and Table Storage locally. This allows you to run and test your applications fast and for free, even without an internet connection. |

### Documents:

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/reference-index?view=azure-cli-latest)
- [Develop Azure Functions by using Visual Studio Code](https://learn.microsoft.com/en-us/azure/azure-functions/functions-develop-vs-code?tabs=node-v4%2Cpython-v2%2Cisolated-process%2Cquick-create&pivots=programming-language-python)
- [Create an Azure service principal with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/azure-cli-sp-tutorial-1?view=azure-cli-latest)
