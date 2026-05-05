# Azure Function Workflow

## Overview
This file defines an Azure Function app that handles incoming HTTP webhook payloads, validates them using Pydantic models, and routes the validated data to Cosmos DB and either Azure Storage Queue or Service Bus Topic.

## Key Components
1. **Imports & Configurations**
   - `azure.functions`, `json`, `logging`
   - `pydantic` models (`Pet`, `Staff`, `Observation`, `WebhookPayload`).
2. **Pydantic Models**
   - Validate payload structure, enforce ISO date parsing, allow extra fields.
3. **Function App Initialization**
   ```python
   app = func.FunctionApp()
   ```
4. **Validation Logic**
   - `valid_content_type`: Checks for `application/json` MIME type.
   - `valid_payload`: Parses and validates JSON against `WebhookPayload` model.
   - `verify_request`: Central validation function returning validated JSON or HTTP error responses.
5. **Routes & Outputs
   1. **`queue_payload`**
      - POST method, triggers on `learn-webhook-queue` Queue.
      *Validates request, writes to Cosmos DB, and sends message to a Queue.*
   2. **`bus_payload`**
      - POST method, triggers on Service Bus Topic `learn-webhook-topic`.
      *Validates request, writes to Cosmos DB, and sends message to a Service Bus.*
6. **Consumers**
   - **Queue Consumer**: Listens on the queue, parses JSON back into Pydantic models, performs alert logic based on pet weight.
     *Checks weight < 20g and logs a warning.*
   - **Service Bus Consumer**: Subscribes to the topic, parses JSON, and logs processing details.
     *Logs incoming message and performs report prep logic.*
