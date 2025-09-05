import json
import logging
import os
import urllib.parse

import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
CODEBUILD_PROJECT_NAME = os.environ.get("CODEBUILD_PROJECT_NAME")

sns_client = boto3.client("sns")
codebuild_client = boto3.client("codebuild")


def handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    for record in event.get("Records", []):
        s3 = record.get("s3", {})
        bucket_name = s3.get("bucket", {}).get("name")
        object_key = s3.get("object", {}).get("key")

        if not bucket_name or not object_key:
            logger.warning("Skipping record due to missing bucket name or object key.")
            continue

        # URL Decode the object key
        object_key = urllib.parse.unquote_plus(object_key)

        # Split the key into parts to identify repo and branch
        key_parts = object_key.split("/")

        # Expected structure: <repo_name>/refs/heads/<branch>
        if len(key_parts) < 4 or key_parts[1] != "refs" or key_parts[2] != "heads":
            logger.info(
                "Skipping object key %s as it does not match expected git ref structure.",
                object_key,
            )
            continue

        repo_name = key_parts[0]

        # Check for review branches: <repo_name>/refs/heads/review/*
        if key_parts[3] == "review":
            if not SNS_TOPIC_ARN:
                logger.error("SNS_TOPIC_ARN not set, cannot send review notification.")
                continue

            branch_name = "/".join(key_parts[3:])
            subject = f"Git push to review branch in {repo_name}"
            message = (
                f"A push was made to a review branch in the '{repo_name}' repository.\n\n"
                f"Branch: {branch_name}\n"
                f"Bucket: {bucket_name}\n"
                f"Full S3 Key: {object_key}\n"
            )
            try:
                sns_client.publish(
                    TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message
                )
                logger.info(
                    "Successfully published review notification for object: %s",
                    object_key,
                )
            except Exception as e:
                logger.error(
                    "Failed to publish SNS message for object %s: %s", object_key, e
                )

        # Check for main branch push: <repo_name>/refs/heads/main
        elif len(key_parts) == 4 and key_parts[3] == "main":
            if not CODEBUILD_PROJECT_NAME:
                logger.error("CODEBUILD_PROJECT_NAME not set, cannot start build.")
                continue

            try:
                response = codebuild_client.start_build(
                    projectName=CODEBUILD_PROJECT_NAME,
                    environmentVariablesOverride=[
                        {"name": "REPO_NAME", "value": repo_name, "type": "PLAINTEXT"},
                        {
                            "name": "S3_BUCKET_NAME",
                            "value": bucket_name,
                            "type": "PLAINTEXT",
                        },
                    ],
                )
                logger.info(
                    "Successfully started CodeBuild project %s for repo %s. Build ID: %s",
                    CODEBUILD_PROJECT_NAME,
                    repo_name,
                    response["build"]["id"],
                )
            except Exception as e:
                logger.error(
                    "Failed to start CodeBuild project for repo %s: %s", repo_name, e
                )

    return {"statusCode": 200, "body": json.dumps("Processing complete.")}
