# Nhận S3 event, lọc file hợp lệ, đẩy job sang SQS và gửi status processing

from typing import Any
import os
import logging
import json
import urllib.parse

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ["AWS_REGION"]
VIDEO_PROCESSING_QUEUE_URL = os.environ["VIDEO_PROCESSING_QUEUE_URL"]
STATUS_CALLBACKS_QUEUE_URL = os.environ["STATUS_CALLBACKS_QUEUE_URL"]
RAW_VIDEOS_BUCKET_NAME = os.environ["RAW_VIDEOS_BUCKET_NAME"]
EXPECTED_OBJECT_SUFFIX = os.environ.get("EXPECTED_OBJECT_SUFFIX", "original.mp4")

sqs = boto3.client("sqs", region_name=AWS_REGION)

def extract_match_id_from_key(key: str) -> str:
    parts = key.split("/")
    if len(parts) < 2:
        raise ValueError(f"Invalid video key format: {key}")
    return parts[1]

def build_job_message(match_id: str, team_id: str, bucket: str, key: str, event_time: str) -> dict[str, Any]:
    return {
        "match_id": match_id,
        "team_id": team_id,
        "s3_bucket": bucket,
        "s3_key": key,
        "uploaded_at": event_time
    }

def build_status_callback(match_id: str, status: str) -> dict[str, Any]:
    return {
        "match_id": match_id,
        "status": status,
        "reason": None,
        "duration_sec": None,
        "emitted_at": None,
    }

def send_message(queue_url: str, payload: dict[str, Any]) -> None:
    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(payload)
    )

def handler(event: dict[str, Any], context: Any) -> dict[str, int]:
    logger.info("Received event: %s", json.dumps(event))

    processed = 0
    skipped = 0

    for record in event.get("Records", []):
        if record.get("eventSource") != "aws:s3":
            skipped += 1
            continue

        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        event_time = record.get("eventTime")

        if bucket != RAW_VIDEOS_BUCKET_NAME:
            skipped += 1
            continue

        if not key.endswith(EXPECTED_OBJECT_SUFFIX):
            skipped += 1
            continue

        parts = key.split("/")
        if len(parts) < 3:
            raise ValueError(f"Invalid key layout, expected team_id/match_id/original.mp4: {key}")

        team_id = parts[0]
        match_id = parts[1]

        job_message = build_job_message(
            match_id=match_id,
            team_id=team_id,
            bucket=bucket,
            key=key,
            event_time=event_time
        )
        send_message(VIDEO_PROCESSING_QUEUE_URL, job_message)

        status_message = build_status_callback(match_id=match_id, status="processing")
        send_message(STATUS_CALLBACKS_QUEUE_URL, status_message)

        processed += 1
        logger.info("Dispatched match_id=%s key=%s", match_id, key)

    return {"processed": processed, "skipped": skipped}