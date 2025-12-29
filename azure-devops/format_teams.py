import json
import os

import requests
from dotenv import load_dotenv
from requests.auth import HTTPBasicAuth

load_dotenv()
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


# Constants
ORGANIZATION = "dasrechtsbijstand"  # Replace with your Azure DevOps organization name
API_VERSION = "7.1"
FILE_PATH = "DAS/teams.json"
base_url = f"https://dev.azure.com/{ORGANIZATION}"
project_id = "f6cf529d-e936-4726-9e52-f08674a7c154"

# Authentication setup
auth = HTTPBasicAuth("", os.getenv("ADO_PAT"))


def get_team_security_group_descriptor(team_id: str) -> str:
    """Retrieve the security group descriptor for a given team."""
    url = f"{base_url}/_apis/projects/{project_id}/teams/{team_id}?api-version=7.1&$expandIdentity=true"
    response = requests.get(
        url, auth=auth, headers={"Content-Type": "application/json"}
    )
    return response.json()["identity"]["subjectDescriptor"]


def get_team_member_descriptors(team_descriptor):
    """
    Retrieve members of a given team and identify administrators.

    :param project_id: The ID of the project.
    :param team_id: The ID of the team.
    :return: A tuple containing a list of members and a list of member administrators.
    """
    members_url = f"https://vssps.dev.azure.com/{ORGANIZATION}/_apis/graph/Memberships/{team_descriptor}?direction=down&api-version=7.1-preview.1"
    response = requests.get(members_url, auth=auth)
    response.raise_for_status()
    members_data = response.json()
    return [m["memberDescriptor"] for m in members_data["value"]]


def get_account_obj_from_descriptor(descriptor: str) -> str:
    url = f"https://vssps.dev.azure.com/{ORGANIZATION}/_apis/identities?subjectDescriptors={descriptor}&api-version=7.1"
    response = requests.get(url, auth=auth)
    data = response.json()

    identity = data["value"][0]

    if identity["subjectDescriptor"][:4] == "aad.":
        return {"principal_name": identity["descriptor"].split("\\")[-1]}

    return {"display_name": identity["providerDisplayName"].split("\\")[-1]}


def format_admin_obj(admin: dict) -> dict:
    if "\\" in admin["displayName"]:
        return {"display_name": admin["displayName"].split("\\")[-1]}
    # TODO: how to get principalname?
    return {"principal_name": admin["uniqueName"]}


def get_member_admins(team_id: str) -> list[dict]:
    url = f"{base_url}/_apis/projects/{project_id}/teams/{team_id}/members?api-version=7.1"
    response = requests.get(
        url, auth=auth, headers={"Content-Type": "application/json"}
    )
    data = response.json()
    admins = [
        format_admin_obj(member_obj["identity"])
        for member_obj in data["value"]
        if member_obj.get("isTeamAdmin", False)
    ]
    return admins


def process_teams_from_json(json_file_path):
    """
    Process teams from a JSON file and retrieve their members and administrators.

    :param json_file_path: Path to the JSON file containing team information.
    :return: List of dictionaries with team members and administrators.
    """
    with open(json_file_path, "r") as file:
        teams = json.load(file)["teams"]

    all_teams_info = []

    for team in teams:
        if team["name"] != "CICC":
            continue

        print(f"> {team['name']}")
        team_id = team["id"]
        team_name = team.get("name", "Unknown Team")

        try:
            # Step 1: Get team descriptor
            team_descriptor = get_team_security_group_descriptor(team_id)
            print(team_descriptor)
            return

            # Step 2: Get team members and member administrators
            member_descriptors = get_team_member_descriptors(
                team_descriptor=team_descriptor
            )

            # Combine member and non-member administrators
            members = [
                get_account_obj_from_descriptor(desc) for desc in member_descriptors
            ]

            admins = get_member_admins(team_id)

            print(f"- found {len(members)} members & {len(admins)} admins.")
            team_info = {
                "id": team["id"],
                "name": team_name,
                "members": members,
                "administrators": admins,
            }
            all_teams_info.append(team_info)
        except requests.HTTPError as http_err:
            print(f"HTTP error occurred for team {team_name}: {http_err}")
        except Exception as err:
            print(f"An error occurred for team {team_name}: {err}")

    return all_teams_info


# Example usage
if __name__ == "__main__":
    teams_info = process_teams_from_json(FILE_PATH)
    # Output or save the teams_info as needed
    # print(json.dumps({"teams": teams_info}, indent=4))
    json.dump({"teams": teams_info}, open(FILE_PATH, "w"), indent=4)
