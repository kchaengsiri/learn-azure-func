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

**Get `APPLICATIONINSIGHTS_CONNECTION_STRING`**

```sh
az monitor app-insights component show \
 --query "[0].connectionString" \
 --output tsv
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

Use the Azure Portal or Microsoft Azure Storage Explorer to see the message.

**List your Storage Accounts** (to find the right name)

```sh
az storage account list \
  --resource-group rg-learn-webhook
  --query "[].name" \
  -o tsv
```

**Create the Queue**

```sh
az storage queue create \
  --name learn-webhook-queue \
  --account-name gamelearnwebhook
```

---

### Service Bus (The Enterprise Route)

Use the Service Bus Explorer directly inside the Azure Portal (under the Topic menu) to "Peek" at the messages.

**Create the Namespace** (must be unique)

_NOTE: SKU: 'Standard' is required for Topics/Subscriptions_

```sh
az servicebus namespace create \
  --name sb-game-learn-webhook \
  --resource-group rg-learn-webhook \
  --location "Southeast Asia" \
  --sku Standard
```

**Create a Topic (for Pub/Sub)**

```sh
az servicebus topic create \
  --name learn-webhook-topic \
  --resource-group rg-learn-webhook \
  --namespace-name sb-game-learn-webhook
```

**Shows the count of messages in the Dead-Letter Queue (DLQ)**

```sh
az servicebus topic subscription show \
  --resource-group rg-learn-webhook \
  --namespace-name sb-game-learn-webhook \
  --topic-name learn-webhook-topic \
  --name AllEventsSubscription \
  --query "countDetails.deadLetterMessageCount"
```

**Get the Connection String**

```sh
az servicebus namespace authorization-rule keys list \
  --resource-group rg-learn-webhook \
  --namespace-name sb-game-learn-webhook \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv
```

**Create a Subscription to the topic**

```sh
az servicebus topic subscription create \
  --name AllEventsSubscription \
  --resource-group rg-learn-webhook \
  --namespace-name sb-game-learn-webhook \
  --topic-name learn-webhook-topic
```

### Setting up the Cloud (RBAC)

When you deploy to Azure, `az login` won't be there.
You must give the Function App's Managed Identity permission to talk to the Service Bus.
Run these commands to finish the setup:

1. Enable System-Assigned Identity for your App

```sh
az functionapp identity assign \
  --name game-learn-webhook \
  --resource-group rg-learn-webhook
```

2. Get Principal ID

_Function App's Principal ID_

```sh
az functionapp identity show \
  --name game-learn-webhook \
  --resource-group rg-learn-webhook \
  --query principalId \
  -o tsv
```

_Your own Principal ID (from `az login`)_

```sh
az ad signed-in-user show --query id -o tsv
```

3. Grant the "Data Receiver" role (for the Consumer)

```sh
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Azure Service Bus Data Receiver" \
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/rg-learn-webhook
```

4. Grant the "Data Sender" role (for the Webhook)

```sh
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Azure Service Bus Data Sender" \
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/rg-learn-webhook
```

### Assign the Cosmos DB Built-in Data Contributor role

1. List Roles (optional)

```sh
az cosmosdb sql role definition list \
  --account-name db-learn-webhook \
  --resource-group rg-learn-webhook
```

2. Create the SQL Role Assignment

```sh
az cosmosdb sql role assignment create \
  --account-name db-learn-webhook \
  --resource-group rg-learn-webhook \
  --scope "/" \
  --principal-id <PRINCIPAL_ID> \
  --role-definition-id 00000000-0000-0000-0000-000000000002
```

_**NOTE:** Standard Cosmos DB Built-in Data Roles_
|Role Name|Role Definition ID|Description|
|---|---|---|
|Cosmos DB Built-in Data Reader|00000000-0000-0000-0000-000000000001|Can read data and metadata.|
|Cosmos DB Built-in Data Contributor|00000000-0000-0000-0000-000000000002|Can read, write, and delete data.|

### Assign Storage Queue Contributor role

1. Create the Role Assignment

```sh
az role assignment create \
  --assignee <PRINCIPAL_ID> \
  --role "Storage Queue Data Contributor" \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-learn-webhook
```

---

