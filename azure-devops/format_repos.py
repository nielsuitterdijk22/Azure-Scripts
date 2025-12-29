"""
Loosely based on https://blog.devopsabcs.com/index.php/2019/06/24/one-project-to-rule-them-all-3/
This script reads two json files for the existing repos & groups (note; not teams).
It queries the existing Access Control Lists (ACLs) per repo and checks which group has contributor rights.
We only extract the contributor rights as we don't segragate further.
"""

import json
import os
from base64 import b64decode

import requests
from dotenv import load_dotenv
from requests.auth import HTTPBasicAuth

load_dotenv()

# Set working dir to repo root
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

organization = "dasrechtsbijstand"
project_id = "f6cf529d-e936-4726-9e52-f08674a7c154"
securityNamespaceId = "2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87"
auth = HTTPBasicAuth("", os.getenv("ADO_PAT"))


def get_permissions(repo_id: str) -> list[dict]:
    token = f"repoV2/{project_id}/{repo_id}"
    url = f"https://dev.azure.com/{organization}/_apis/accesscontrollists/{securityNamespaceId}?api-version=7.2-preview.1&token={token}"
    return requests.get(
        url, auth=auth, headers={"Content-Type": "application/json"}
    ).json()["value"]


def decode_sid(descriptor: str) -> str:
    sid_base64 = descriptor.split(".")[1]

    # These may need padding
    sid_base64 += "=" * (4 - len(sid_base64) % 4)
    return b64decode(sid_base64).decode("utf-8")


def has_contributor(allow: int) -> bool:
    if not (0 <= allow <= 2**19):
        raise ValueError(f"Unexpected allow integer: {allow}")
    permission_bits = format(allow & 0xFFFF, "016b")
    return permission_bits[-2] == "1"


repos = json.load(open("DAS/repos.json", "r"))
repos = repos["repositories"]
groups = json.load(open("DAS/groups.json", "r"))
groups = groups["groups"]
teams = json.load(open("DAS/teams.json", "r"))

print("> Mapping group SID")
sid_name_map = {}
for group in groups:
    sid_name_map[decode_sid(group["descriptor"])] = group["name"]

print("> Fetching & mapping ACLs")
for repo in repos:
    repo["contributors"] = []

    permissions = get_permissions(repo["id"])
    if len(permissions) != 1:
        print(f"> Found repo without ACLs: {repo['name']}")
        continue

    acl = permissions[0]["acesDictionary"]
    acl = {k: v for k, v in acl.items() if "TeamFoundation" in k}

    for group, metadata in acl.items():
        if has_contributor(metadata.get("allow", 0)):
            group_sid = metadata["descriptor"].split(";")[1]
            if group_sid in sid_name_map:
                repo["contributors"].append(sid_name_map[group_sid])
            else:
                print(f"> Group not found for repo {repo['name']}")

    # Remove id as it's not part of the desired vars file -- teams cannot specify this before creation
    # repo.pop("id")

    # Remove default branch if it's the default to minimize config
    if repo["default_branch"] == "refs/heads/main":
        repo.pop("default_branch")

print("> Storing repos with contributors")
json.dump({"repositories": repos}, open("DAS/repos.json", "w"), indent=4)
