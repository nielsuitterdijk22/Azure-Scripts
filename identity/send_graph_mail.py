import asyncio

from azure.identity import DefaultAzureCredential
from msgraph import GraphServiceClient
from msgraph.generated.models.body_type import BodyType
from msgraph.generated.models.email_address import EmailAddress
from msgraph.generated.models.item_body import ItemBody
from msgraph.generated.models.message import Message
from msgraph.generated.models.recipient import Recipient
from msgraph.generated.users.item.send_mail.send_mail_post_request_body import (
    SendMailPostRequestBody,
)

# To initialize your graph_client, see https://learn.microsoft.com/en-us/graph/sdks/create-client?from=snippets&tabs=python
request_body = SendMailPostRequestBody(
    message=Message(
        subject="Graph mail via DefaultAzureCredential",
        body=ItemBody(
            content_type=BodyType.Text,
            content="This email was sent using your az login context!",
        ),
        to_recipients=[
            Recipient(email_address=EmailAddress(address="n.uitterdijk@das.nl"))
        ],
    ),
    save_to_sent_items=False,
)

scopes = ["Mail.Send"]
credentials = DefaultAzureCredential()
client = GraphServiceClient(credentials=credentials, scopes=scopes)


async def send_email():
    # Use a different enabled mailbox to send from
    await client.users.by_user_id("n.uitterdijk@das.nl").send_mail.post(request_body)
    print("✅ Mail sent successfully")


try:
    asyncio.run(send_email())
except Exception as e:
    print(f"❌ Failed: {e}")
