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
# Full payload
$ curl -X POST http://localhost:7071/api/json_payload \
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
# Minimum payload
$ curl -i -X POST "https://<YOUR_APP_NAME>.azurewebsites.net/api/json_payload?code=<YOUR_FUNCTION_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "pet_weight_check",
    "pet": { "id": "P-CLOUD-01" },
    "observation": {
      "weight": 52.2,
      "weight_at": "2026-04-24T10:15:00Z",
    },
    "staff": { "id": "S-007" }
  }'

# Custom payload
$ curl -i -X POST "https://<YOUR_APP_NAME>.azurewebsites.net/api/json_payload?code=<YOUR_FUNCTION_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "pet_weight_check",
    "pet": {
      "id": "P-CLOUD-02",
      "species": "Parrotlet",
      "age": {
        "years":2,
        "months":4,
        "days":185
      }
    },
    "observation": {
      "weight": 72.6,
      "weight_at": "2026-05-05T08:15:00Z",
      "note": "any comment message or note"
    },
    "staff": {
      "id": "S-022",
      "name": "Nana",
      "email": "nana@email.net"
    }
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
