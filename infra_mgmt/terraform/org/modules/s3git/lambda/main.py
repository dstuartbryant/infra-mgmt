import json
import logging
import os
import urllib.parse

import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")
if not sns_topic_arn:
    logger.error("SNS_TOPIC_ARN environment variable not set.")
    raise ValueError("SNS_TOPIC_ARN environment variable not set.")

sns_client = boto3.client("sns")


def handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    for record in event.get("Records", []):
        s3 = record.get("s3", {})
        bucket_name = s3.get("bucket", {}).get("name")
        object_key = s3.get("object", {}).get("key")

        if not bucket_name or not object_key:
            logger.warning("Skipping record due to missing bucket name or object key.")
            continue

        # URL Decode the object key in case it has url-encoded characters
        object_key = urllib.parse.unquote_plus(object_key)

        # Split the key into parts to identify repo and branch
        key_parts = object_key.split("/")

        # Expected structure: <repo_name>/refs/heads/review/<branch_name>
        if (
            len(key_parts) >= 4
            and key_parts[1] == "refs"
            and key_parts[2] == "heads"
            and key_parts[3] == "review"
        ):
            repo_name = key_parts[0]
            branch_name = "/".join(key_parts[3:])

            subject = f"Git push to review branch in {repo_name}"
            message = (
                f"A push was made to a review branch in the '{repo_name}' repository.\n\n"
                f"Branch: {branch_name}\n"
                f"Bucket: {bucket_name}\n"
                f"Full S3 Key: {object_key}\n"
            )

            logger.info("Publishing message to SNS topic: %s", sns_topic_arn)

            try:
                sns_client.publish(
                    TopicArn=sns_topic_arn, Subject=subject, Message=message
                )
                logger.info("Successfully published message for object: %s", object_key)
            except Exception as e:
                logger.error(
                    "Failed to publish message for object %s: %s", object_key, e
                )
                # Depending on requirements, you might want to handle this error
                # differently. For example, by raising an exception to have Lambda
                # retry the function.

    return {"statusCode": 200, "body": json.dumps("Processing complete.")}
