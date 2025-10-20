import json
import logging
import os

import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

SNS_BUILD_STATUS_TOPIC_ARN = os.environ.get("SNS_BUILD_STATUS_TOPIC_ARN")
AWS_REGION = os.environ.get("AWS_REGION")

sns_client = boto3.client("sns")


def handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    build_id = event["detail"]["build-id"]
    project_name = event["detail"]["project-name"]
    build_status = event["detail"]["build-status"]

    log_group = f"/aws/codebuild/{project_name}"
    log_stream_encoded = event["detail"]["additional-information"]["logs"]["stream-name"].replace("/", "%252F")
    deep_link = f"https://{AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region={AWS_REGION}#logsV2:log-groups/log-group/{log_group}/log-events/{log_stream_encoded}"

    subject = f"CodeBuild {build_status.upper()} for {project_name}"
    message = (
        f"The CodeBuild project '{project_name}' has completed with status: {build_status.upper()}.\n\n"
        f"Build ID: {build_id}\n\n"
        f"View the detailed logs here:\n{deep_link}\n"
    )

    try:
        sns_client.publish(
            TopicArn=SNS_BUILD_STATUS_TOPIC_ARN, Subject=subject, Message=message
        )
        logger.info("Successfully published build status notification.")
    except Exception as e:
        logger.error("Failed to publish SNS message: %s", e)

    return {"statusCode": 200, "body": json.dumps("Processing complete.")}
