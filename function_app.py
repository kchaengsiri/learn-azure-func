import azure.functions as func
import json
import logging
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
from typing import Optional
from datetime import datetime


# class DateTimeEncoder(json.JSONEncoder):
#     def default(self, obj):
#         if isinstance(obj, datetime):
#             # Formats to ISO 8601 (e.g., 2026-04-26T12:00:00Z)
#             return obj.isoformat().replace("+00:00", "Z")
#         return super().default(obj)


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
    model_config = ConfigDict(extra="allow")


app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.route(
    route="webhook_test",
    methods=["GET"],
)
def webhook_test(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("webhook_test triggered")

    name = req.params.get("name")
    if name:
        return func.HttpResponse(f"Hello, {name}.")
    else:
        return func.HttpResponse(
            body="Pass a name in the query string for a personalized response.",
            status_code=200,
        )


@app.route(
    route="json_payload",
    methods=["POST"],
    auth_level=func.AuthLevel.FUNCTION,
)
@app.cosmos_db_output(
    arg_name="outputDocument",
    database_name="ObservationLog",
    container_name="ObservationContainer",
    connection="CosmosDbConnectionString",
)
def json_payload(
    req: func.HttpRequest,
    outputDocument: func.Out[func.Document],
) -> func.HttpResponse:
    logging.info("json_payload triggered.")

    # Check Content-Type (Professional touch)
    content_type = req.headers.get("Content-Type", "")
    if "application/json" not in content_type.lower():
        return func.HttpResponse(
            body="Unsupported Media Type: expected application/json",
            status_code=415,
        )

    try:
        # Extract JSON paylaod
        payload = req.get_json()
        logging.info(f"Payload: {payload}")
        # Validate payload
        data = WebhookPayload.model_validate(payload)
        logging.info(f"Validated: {data}")

        # Convert Pydantic model to a standard dictionary
        document = data.model_dump(mode="json")

        # Cosmos DB requires a unique "id" at the root of every document
        # We'll combine the pet ID and a timestamp to make it unique
        document["id"] = f"{data.pet.id}-{int(datetime.now().timestamp())}"

        # Send the document to the Output Binding
        outputDocument.set(func.Document.from_dict(document))

        return func.HttpResponse(
            # body=data.model_dump_json(),
            # body=json.dumps(document, indent=2, sort_keys=True, cls=DateTimeEncoder),
            body=json.dumps(document, indent=2, sort_keys=True),
            status_code=200,
            mimetype="application/json",
        )

    except ValidationError as e:
        # e.json() returns a string, but you can also use e.errors() for a list
        logging.error(f"Validation error: {e.errors()}")
        return func.HttpResponse(
            body=e.json(),
            status_code=422,
            mimetype="application/json",
        )
    except ValueError:
        return func.HttpResponse(
            body="Invalid JSON format",
            status_code=400,
        )
