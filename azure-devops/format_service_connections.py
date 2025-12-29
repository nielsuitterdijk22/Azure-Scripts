import json
import os

import requests
from dotenv import load_dotenv
from requests.auth import HTTPBasicAuth

load_dotenv()

# Set working dir to repo root
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

organization = "dasrechtsbijstand"
project_id = "f6cf529d-e936-4726-9e52-f08674a7c154"
securityNamespaceId = "49b48001-ca20-4adc-8111-5b60c903a50c"  # Service Connections
auth = HTTPBasicAuth("", os.getenv("ADO_PAT"))


def get_permissions(endpoint_id: str) -> list[dict]:
    url = f"https://dev.azure.com/{organization}/{project_id}/_apis/pipelines/pipelinePermissions/endpoint/{endpoint_id}"
    response = requests.get(
        url, auth=auth, headers={"Content-Type": "application/json"}
    )
    return response.json()


def pipeline_id_to_name(pipeline_id: str) -> str:
    pipeline = [pipe for pipe in pipelines if pipe["id"] == pipeline_id]
    return pipeline[0]["name"]


def has_contributor(allow: int) -> bool:
    if not (0 <= allow <= 2**19):
        raise ValueError(f"Unexpected allow integer: {allow}")
    permission_bits = format(allow & 0xFFFF, "016b")
    return permission_bits[-2] == "1"


service_connections = json.load(open("DAS/service_connections.json", "r"))
service_connections = service_connections["service_connections"]

pipelines = json.load(open("DAS/pipelines.json", "r"))
pipelines = pipelines["pipelines"]

print("> Getting & matching service connection permissions")
for service_connection in service_connections:
    print(f"> Service Connection: {service_connection['name']}")

    permissions = get_permissions(service_connection["id"])

    pipeline_ids = [pipe["id"] for pipe in permissions["pipelines"]]

    service_connection["authorized_pipelines"] = [
        {"id": pipe_id, "name": pipeline_id_to_name(pipe_id)}
        for pipe_id in pipeline_ids
    ]

print("Storing repos with contributors")
json.dump(
    {"service_connections": service_connections},
    open("DAS/service_connections.json", "w"),
    indent=4,
)
