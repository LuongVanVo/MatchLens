# Nhận object trong raw-clips/, tạo job MediaConvert, output sang clips/

import urllib.parse
import json
from typing import Any
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ["AWS_REGION"]
MEDIACONVERT_ROLE_ARN = os.environ["MEDIACONVERT_ROLE_ARN"]
PROCESSED_HIGHLIGHTS_BUCKET = os.environ["PROCESSED_HIGHLIGHTS_BUCKET"]
MEDIACONVERT_INPUT_PREFIX = os.environ.get("MEDIACONVERT_INPUT_PREFIX", "raw-clips/")
MEDIACONVERT_OUTPUT_PREFIX = os.environ.get("MEDIACONVERT_OUTPUT_PREFIX", "clips/")

mc_control = boto3.client("mediaconvert", region_name=AWS_REGION)

def get_mediaconvert_client():
    endpoints = mc_control.describe_endpoints(MaxResults=1)
    endpoint_url = endpoints["Endpoints"][0]["Url"]
    return boto3.client("mediaconvert", region_name=AWS_REGION, endpoint_url=endpoint_url)

def build_output_prefix(input_key: str) -> str:
    if not input_key.startswith(MEDIACONVERT_INPUT_PREFIX):
        raise ValueError(f"Unexpected key prefix: {input_key}")

    suffix = input_key[len(MEDIACONVERT_INPUT_PREFIX):]
    if suffix.endswith(".mp4"):
        suffix = suffix[:-4]

    return f"{MEDIACONVERT_OUTPUT_PREFIX}{suffix}/"

def create_job(input_key: str) -> dict[str, Any]:
    client = get_mediaconvert_client()
    output_prefix = build_output_prefix(input_key)

    return client.create_job(
        Role=MEDIACONVERT_ROLE_ARN,
        Settings={
            "Inputs": [
                {
                    "FileInput": f"s3://{PROCESSED_HIGHLIGHTS_BUCKET}/{input_key}",
                }
            ],
            "OutputGroups": [
                {
                    "Name": "File Group",
                    "OutputGroupSettings": {
                        "Type": "FILE_GROUP_SETTINGS",
                        "FileGroupSettings": {
                            "Destination": f"s3://{PROCESSED_HIGHLIGHTS_BUCKET}/{output_prefix}",
                        },
                    },
                    "Outputs": [
                        {
                            "ContainerSettings": {
                                "Container": "MP4",
                            },
                            "VideoDescription": {
                                "CodecSettings": {
                                    "Codec": "H_264",
                                    "H264Settings": {
                                        "RateControlMode": "QVBR",
                                        "SceneChangeDetect": "TRANSITION_DETECTION",
                                    },
                                },
                            },
                            "AudioDescriptions": [
                                {
                                    "CodecSettings": {
                                        "Codec": "AAC",
                                        "AacSettings": {
                                            "Bitrate": 96000,
                                            "CodingMode": "CODING_MODE_2_0",
                                            "SampleRate": 48000,
                                        },
                                    }
                                }
                            ],
                        }
                    ],
                }
            ],
        },
    )

def handler(event: dict[str, Any], context: Any) -> dict[str, int]:
    logger.info("Received event: %s", json.dumps(event))

    created = 0
    skipped = 0

    for record in event.get("Records", []):
        if record.get("eventSource") != "aws:s3":
            skipped += 1
            continue

        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        if bucket != PROCESSED_HIGHLIGHTS_BUCKET:
            skipped += 1
            continue

        if not key.startswith(MEDIACONVERT_INPUT_PREFIX):
            skipped += 1
            continue

        response = create_job(key)
        created += 1
        logger.info("Created MediaConvert job: %s", response["Job"]["Id"])

    return {"created": created, "skipped": skipped}
    