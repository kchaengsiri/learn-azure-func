#!/usr/bin/env bash

set -euo pipefail

#
# ============================================================
# kc-learn-az Platform - Azure Infrastructure Bootstrap
# ============================================================
#
# This script creates:
#
# - Resource Group
# - Storage Account
# - Function App
# - CosmosDB Account + Database + Containers
# - Service Bus Namespace + Topics + Subscriptions
# - Application Insights
# - Key Vault
#
# ============================================================
#

#
# -----------------------------
# CONFIGURATION
# -----------------------------
#

PROJECT="kc-learn-az-platform"

LOCATION="southeastasia"

RESOURCE_GROUP="rg-${PROJECT}"

STORAGE_ACCOUNT="stkc-learn-azplat$(openssl rand -hex 4)" # must be globally unique
FUNCTION_APP="func-kc-learn-az-platform"
APP_INSIGHTS="appi-kc-learn-az-platform"

COSMOS_ACCOUNT="cosmos-kc-learn-az-platform"
COSMOS_DB="incoming_events"

COSMOS_RAW_CONTAINER="raw_events"
COSMOS_PROCESSED_CONTAINER="processed_events"

SERVICEBUS_NAMESPACE="sb-kc-learn-az-platform"

TOPIC_EVENTS="donation-events"

SUBSCRIPTION_LEDGER="ledger"
SUBSCRIPTION_EMAILS="emails"
SUBSCRIPTION_ANALYTICS="analytics"
SUBSCRIPTION_RECONCILIATION="reconciliation"

KEYVAULT_NAME="kv-kc-learn-az-platform"

PYTHON_VERSION="3.11"

#
# -----------------------------
# FLAGS
# -----------------------------
#

DO_CLEANUP=false
ENABLE_APP_INSIGHTS=false
FORCE_SECRET_UPDATE=false
SKIP_LOGIN=false
SKIP_REGISTER_PROVIDERS=false

for arg in "$@"; do
  case $arg in
    --appinsights)
      ENABLE_APP_INSIGHTS=true
      ;;
    --skip-login)
      SKIP_LOGIN=true
      ;;
    --skip-register)
      SKIP_REGISTER_PROVIDERS=true
      ;;
    --cleanup)
      DO_CLEANUP=true
      ;;
    --help)
      echo "Usage:"
      echo "  --appinsights    Enable Application Insights"
      echo "  --skip-login     Skip az login"
      echo "  --skip-register  Skip az provider register"
      echo "  --cleanup        Delete resource group"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

#
# -----------------------------
# CLEANUP
# -----------------------------
#

if [ "$DO_CLEANUP" = true ]; then
  echo "==> Cleaning up resource group: $RESOURCE_GROUP"
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  exit 0
fi

#
# -----------------------------
# LOGIN
# -----------------------------
#

if [ "$SKIP_LOGIN" = false ]; then
  echo "==> Azure Login"
  az login
else
  echo "==> Skipping Azure login"
fi

SUBSCRIPTION_ID=$(az account show --query id --output tsv)

if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "Cannot find logged in account"
  exit 0
else
  echo "Using subscription: $SUBSCRIPTION_ID"
fi

#
# -----------------------------
# REGISTER RESOURCE PROVIDERS
# -----------------------------
#

if [ "$SKIP_REGISTER_PROVIDERS" = false ]; then
  echo "==> Registering required Azure providers"

  for provider in \
    Microsoft.Storage \
    Microsoft.Web \
    Microsoft.Insights \
    Microsoft.DocumentDB \
    Microsoft.ServiceBus \
    Microsoft.KeyVault \
    Microsoft.ManagedIdentity \
    Microsoft.Authorization
  do
    echo "Checking $provider..."

    state=$(
      az provider show \
        --namespace "$provider" \
        --query "registrationState" \
        --output tsv
    )

    if [ "$state" != "Registered" ]; then
      echo "Registering $provider..."
      az provider register --namespace "$provider" --wait
    else
      echo "$provider already registered"
    fi
  done
else
  echo "==> Skipping Azure providers Registering"
fi

#
# -----------------------------
# RESOURCE GROUP
# -----------------------------
#

echo "==> Creating Resource Group [$RESOURCE_GROUP]"

az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

#
# -----------------------------
# STORAGE ACCOUNT
# -----------------------------
# | SKU           | Meaning                      |
# | ------------- | ---------------------------- |
# | Standard_LRS  | Cheap local redundancy       |
# | Standard_ZRS  | Better production redundancy |
# | Standard_GRS  | Cross-region backup          |
# | Standard_GZRS | Enterprise-grade resilience  |
#

echo "==> Creating Storage Account"

az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS

#
# -----------------------------
# APPLICATION INSIGHTS
# -----------------------------
#

if [ "$ENABLE_APP_INSIGHTS" = true ]; then
  echo "==> Creating Application Insights"
  az monitor app-insights component create \
    --app "$APP_INSIGHTS" \
    --location "$LOCATION" \
    --resource-group "$RESOURCE_GROUP" \
    --application-type web
else
  echo "==> Skipped Application Insights"
fi

#
# -----------------------------
# FUNCTION APP
# -----------------------------
#

echo "==> Creating Function App"

az functionapp create \
  --resource-group "$RESOURCE_GROUP" \
  --consumption-plan-location "$LOCATION" \
  --os-type Linux \
  --runtime python \
  --runtime-version "$PYTHON_VERSION" \
  --functions-version 4 \
  --name "$FUNCTION_APP" \
  --storage-account "$STORAGE_ACCOUNT"

#
# -----------------------------
# COSMOS DB
# -----------------------------
#

echo "==> Creating CosmosDB Account"

az cosmosdb create \
  --name "$COSMOS_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --kind GlobalDocumentDB \
  --default-consistency-level Session \
  --enable-free-tier true

#
# -----------------------------
# COSMOS DATABASE
# -----------------------------
#

echo "==> Creating Cosmos Database"

az cosmosdb sql database create \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$COSMOS_DB"

#
# -----------------------------
# RAW EVENTS CONTAINER
# -----------------------------
#

echo "==> Creating Cosmos Container: raw_events"

az cosmosdb sql container create \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --database-name "$COSMOS_DB" \
  --name "$COSMOS_RAW_CONTAINER" \
  --partition-key-path "/provider"

#
# -----------------------------
# PROCESSED EVENTS CONTAINER
# -----------------------------
#

echo "==> Creating Cosmos Container: processed_events"

az cosmosdb sql container create \
  --account-name "$COSMOS_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --database-name "$COSMOS_DB" \
  --name "$COSMOS_PROCESSED_CONTAINER" \
  --partition-key-path "/provider"

#
# -----------------------------
# SERVICE BUS
# -----------------------------
#

echo "==> Creating Service Bus Namespace"

az servicebus namespace create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SERVICEBUS_NAMESPACE" \
  --location "$LOCATION" \
  --sku Standard

#
# -----------------------------
# SERVICE BUS TOPIC
# -----------------------------
#

echo "==> Creating Service Bus Topic"

az servicebus topic create \
  --resource-group "$RESOURCE_GROUP" \
  --namespace-name "$SERVICEBUS_NAMESPACE" \
  --name "$TOPIC_EVENTS"

#
# -----------------------------
# SUBSCRIPTIONS
# -----------------------------
#

echo "==> Creating Topic Subscriptions"

for SUB in \
  "$SUBSCRIPTION_LEDGER" \
  "$SUBSCRIPTION_EMAILS" \
  "$SUBSCRIPTION_ANALYTICS" \
  "$SUBSCRIPTION_RECONCILIATION"
do
  az servicebus topic subscription create \
    --resource-group "$RESOURCE_GROUP" \
    --namespace-name "$SERVICEBUS_NAMESPACE" \
    --topic-name "$TOPIC_EVENTS" \
    --name "$SUB"
done

#
# -----------------------------
# KEY VAULT
# -----------------------------
#

echo "==> Creating Key Vault"

az keyvault create \
  --name "$KEYVAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION"

#
# -----------------------------
# CONNECTION STRINGS
# -----------------------------
#

echo "==> Retrieving Application Insights Connection String"

APPINSIGHTS_CONNECTION_STRING=""
if [ "$ENABLE_APP_INSIGHTS" = true ]; then
  APPINSIGHTS_CONNECTION_STRING=$(
    az monitor app-insights component show \
      --app "$APP_INSIGHTS" \
      --resource-group "$RESOURCE_GROUP" \
      --query connectionString \
      --output tsv
  )
fi

echo "==> Retrieving Cosmos Connection String"

COSMOS_CONNECTION=$(
  az cosmosdb keys list \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --type connection-strings \
    --query "connectionStrings[0].connectionString" \
    --output tsv
)

echo "==> Retrieving Service Bus Connection String"

SERVICEBUS_CONNECTION=$(
  az servicebus namespace authorization-rule keys list \
    --resource-group "$RESOURCE_GROUP" \
    --namespace-name "$SERVICEBUS_NAMESPACE" \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString \
    --output tsv
)

#
# -----------------------------
# FUNCTION APP SETTINGS
# -----------------------------
#

echo "==> Configuring Function App Settings"

SETTINGS=(
  "CosmosDbConnectionString=$COSMOS_CONNECTION"
  "ServiceBusConnection=$SERVICEBUS_CONNECTION"
)

if [ "$ENABLE_APP_INSIGHTS" = true ]; then
  SETTINGS+=("APPLICATIONINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CONNECTION_STRING")
fi

az functionapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FUNCTION_APP" \
  --settings "${SETTINGS[@]}"

#
# -----------------------------
# GRANT SET SECRET PERMISSION
# -----------------------------
#

echo "==> Granting Key Vault permission to current user"

USER_OBJECT_ID=$(
  az ad signed-in-user show \
    --query id \
    --output tsv
)
SCOPE_ID=$(
  az keyvault show \
    --name "$KEYVAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id \
    --output tsv
)

az role assignment create \
  --assignee "$USER_OBJECT_ID" \
  --role "Key Vault Secrets Officer" \
  --scope "$SCOPE_ID" \
  || echo "Role already exists"


echo "Waiting for RBAC propagation..."

sleep 20

#
# -----------------------------
# OPTIONAL PAYPAL SECRET
# -----------------------------
#

echo "==> Checking for deleted Key Vault"

if az keyvault list-deleted \
  --query "[?name=='$KEYVAULT_NAME']" \
  -o tsv | grep -q "$KEYVAULT_NAME"; then

  echo "Found soft-deleted Key Vault, purging..."

  az keyvault purge \
    --name "$KEYVAULT_NAME" \
    --location "$LOCATION"

  echo "Waiting for purge to complete..."
  sleep 10
else
  echo "No deleted Key Vault found"
fi


echo "==> Ensuring PayPal webhook secret exists"

if az keyvault secret show \
  --vault-name "$KEYVAULT_NAME" \
  --name "PAYPAL-WEBHOOK-SECRET" \
  >/dev/null 2>&1; && [ "$FORCE_SECRET_UPDATE" = false ]; then
  echo "Secret exists, skipping"
else
  echo "Setting secret"

  az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "PAYPAL-WEBHOOK-SECRET" \
    --value "replace-me"
fi

# if az keyvault secret show \
#   --vault-name "$KEYVAULT_NAME" \
#   --name "PAYPAL-WEBHOOK-SECRET" \
#   >/dev/null 2>&1; then

#   echo "Secret already exists, skipping creation"

# else
#   echo "Creating placeholder PayPal webhook secret"

#   az keyvault secret set \
#     --vault-name "$KEYVAULT_NAME" \
#     --name "PAYPAL-WEBHOOK-SECRET" \
#     --value "replace-me"
# fi



#
# -----------------------------
# DONE
# -----------------------------
#

echo ""
echo "========================================"
echo "Azure Infrastructure Setup Complete"
echo "========================================"
echo ""
echo "Resource Group:      $RESOURCE_GROUP"
echo "Function App:        $FUNCTION_APP"
echo "CosmosDB Account:    $COSMOS_ACCOUNT"
echo "Service Bus:         $SERVICEBUS_NAMESPACE"
echo "Key Vault:           $KEYVAULT_NAME"
echo ""
echo ""
echo "Check costs:"
echo "https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
