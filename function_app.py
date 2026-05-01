import azure.functions as func
import json
import logging
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
from typing import Optional
from datetime import datetime


# Models
class Pet(BaseModel):
    id: str
    name: Optional[str] = None

    # Allows additional fields like 'species' and 'sex' to be preserved
    model_config = ConfigDict(extra="allow")


class Staff(BaseModel):
    id: str
    name: Optional[str] = None

    # Allows additional fields
    model_config = ConfigDict(extra="allow")


class Observation(BaseModel):
    note: Optional[str] = None
    unit: Optional[str] = "g"
    weight: float
    weight_at: datetime

    # Allows additional fields
    model_config = ConfigDict(extra="allow")

    @field_validator("weight_at", mode="before")
    @classmethod
    def parse_date_string(cls, v):
        if isinstance(v, str):
            # Enforce YYYY-MM-DD or ISO format
            # If it's just numbers like "20260424", this will fail (good!)
            try:
                # Attempt to parse ISO format first (standard)
                return datetime.fromisoformat(v.replace("Z", "+00:00"))
            except ValueError:
                # If you specifically want to support YYYYMMDD, add it here:
                # return datetime.strptime(v, "%Y%m%d")
                raise ValueError(
                    "Date must be in ISO format (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ)"
                )
        return v


class WebhookPayload(BaseModel):
    # Maps "event" from JSON to "event_type"
    event_type: str = Field(..., alias="event")
    pet: Pet
    observation: Observation
    staff: Staff

    # Allows additional fields
    model_config = ConfigDict(
        extra="allow",
        populate_by_name=True,  # This allows both 'event' and 'event_type' to work
    )


# Init Function App
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def valid_content_type(req: func.HttpRequest):
    # Check Content-Type
    content_type = req.headers.get("Content-Type", "")
    logging.debug(f"valid_content_type: {content_type}")
    if "application/json" in content_type.lower():
        return True
    return False


def valid_payload(req: func.HttpRequest):
    try:
        # Extract JSON paylaod
        payload = req.get_json()
        logging.debug(f"valid_payload::payload: {payload}")
        # Validate payload
        data = WebhookPayload.model_validate(payload)
        logging.debug(f"valid_payload::data: {data}")
        # Convert Pydantic model to a standard dictionary
        document = data.model_dump(mode="json")
        logging.debug(f"valid_payload::document: {document}")

        # Cosmos DB requires a unique "id" at the root of every document
        # We'll combine the pet ID and a timestamp to make it unique
        document["id"] = f"{data.pet.id}-{int(datetime.now().timestamp())}"
        logging.debug(f"valid_payload::document[id]: {document['id']}")

        return None, document

    except ValidationError as e:
        # e.json() returns a string, but you can also use e.errors() for a list
        logging.error(f"Validation error: {e.json()}")
        return e.json(), None
    except ValueError as e:
        logging.error(f"Value error: {e.json()}")
        return "Invalid JSON format", None


def verify_request(req):
    # Check Content-Type
    if not valid_content_type(req):
        return func.HttpResponse(
            body="Unsupported Media Type: expected application/json",
            status_code=415,
        )

    # Check Body Payload
    err, document = valid_payload(req)
    if err:
        return func.HttpResponse(body=err, status_code=400)

    return json.dumps(document, indent=2, sort_keys=True)


# Queue Storage
@app.route(
    route="queue_payload",
    methods=["POST"],
    auth_level=func.AuthLevel.FUNCTION,
)
@app.cosmos_db_output(
    arg_name="cosmos",
    database_name="ObservationLog",
    container_name="ObservationContainer",
    connection="CosmosDbConnectionString",
)
@app.queue_output(
    arg_name="queue",
    queue_name="learn-webhook-queue",
    connection="AzureWebJobsStorage",
)
def queue_payload(
    req: func.HttpRequest,
    cosmos: func.Out[func.Document],
    queue: func.Out[str],
) -> func.HttpResponse:
    logging.info("queue_payload triggered.")

    json_doc = verify_request(req)

    # Store the document to the Cosmos DB
    cosmos.set(func.Document.from_json(json_doc))

    # Send the document to the Queue
    queue.set(json_doc)

    return func.HttpResponse(
        body=json_doc,
        status_code=200,
        mimetype="application/json",
    )


# Service Bus
@app.route(
    route="bus_payload",
    methods=["POST"],
    auth_level=func.AuthLevel.FUNCTION,
)
@app.cosmos_db_output(
    arg_name="cosmos",
    database_name="ObservationLog",
    container_name="ObservationContainer",
    connection="CosmosDbConnectionString",
)
@app.service_bus_topic_output(
    arg_name="bus",
    topic_name="learn-webhook-topic",
    connection="ServiceBusConnection",
)
def bus_payload(
    req: func.HttpRequest,
    cosmos: func.Out[func.Document],
    bus: func.Out[str],
) -> func.HttpResponse:
    logging.info("bus_payload triggered.")

    json_doc = verify_request(req)

    # Store the document to the Cosmos DB
    cosmos.set(func.Document.from_json(json_doc))

    # Send the document to the Service Bus
    bus.set(json_doc)

    return func.HttpResponse(
        body=json_doc,
        status_code=200,
        mimetype="application/json",
    )


# Queue Consumer
@app.queue_trigger(
    arg_name="msg",
    queue_name="learn-webhook-queue",
    connection="AzureWebJobsStorage",
)
def queue_consumer(msg: func.QueueMessage):
    # Get the message body (the JSON string)
    message_body = msg.get_body().decode("utf-8")
    logging.info(f"Storage Queue Consumer received: {message_body}")

    # Step: Parse the JSON back into your Pydantic model
    data = WebhookPayload.model_validate_json(message_body)

    # Example Business Logic: Check bird weight
    if data.observation.weight < 20:
        logging.warning(
            f"ALERT: {data.pet.name} (ID: {data.pet.id}) has a critically low weight!"
        )


# Bus Consumer
@app.service_bus_topic_trigger(
    arg_name="msg",
    topic_name="learn-webhook-topic",
    subscription_name="AllEventsSubscription",
    connection="ServiceBusConnection",
)
def service_bus_consumer(msg: func.ServiceBusMessage):
    # Service Bus handles strings directly
    message_body = str(msg.get_body().decode("utf-8"))
    logging.info(f"Service Bus Consumer received: {message_body}")

    # Step: Parse the JSON back into your Pydantic model
    data = WebhookPayload.model_validate_json(message_body)

    # Logic: Perform a different task (e.g., prep for a report)
    logging.info(f"Processing report data for pet: {data.pet.name}")
