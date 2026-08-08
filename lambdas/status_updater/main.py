from transitions import is_valid_transition
from typing import Any
import boto3
import logging
import os
import json
import psycopg2

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ["AWS_REGION"]
DB_SECRET_ARN = os.environ["DB_SECRET_ARN"]

secrets_manager = boto3.client("secretsmanager", region_name=AWS_REGION)

def load_db_config() -> dict[str, Any]: 
    response = secrets_manager.get_secret_value(SecretId=DB_SECRET_ARN)
    secret = json.loads(response["SecretString"])

    return {
        "host": secret["host"],
        "port": int(secret["port"]),
        "dbname": secret["dbname"],
        "user": secret["username"],
        "password": secret["password"],
    }

def get_connection():
    cfg = load_db_config()
    return psycopg2.connect(
        host=cfg["host"],
        port=cfg["port"],
        dbname=cfg["dbname"],
        user=cfg["user"],
        password=cfg["password"],
    )

def update_status(match_id: str, next_status: str, reason: str | None, duration_sec: int | None) -> None:
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT status
                FROM matches 
                WHERE id = %s
                FOR UPDATE
                """,
                (match_id,)
            )
            row = cur.fetchone()

            if row is None:
                raise ValueError(f"Match not found: {match_id}")

            current_status = row[0]

            if current_status == next_status:
                logger.info("Idempotent update ignored: match_id=%s status=%s", match_id, next_status)
                conn.commit()
                return

            if not is_valid_transition(current_status, next_status):
                logger.warning(
                    "Invalid staus transition ignored: match_id=%s %s -> %s",
                    match_id,
                    current_status,
                    next_status
                )
                conn.commit()
                return

            cur.execute(
                """
                UPDATE matches
                SET status = %s,
                    error_message = CASE WHEN %s = 'failed' THEN %s ELSE error_message END,
                    duration_sec = CASE WHEN %s = 'completed' THEN %s ELSE duration_sec END,
                    updated_at = NOW()
                WHERE id = %s
                """,
                (
                    next_status,
                    next_status,
                    reason,
                    next_status,
                    duration_sec,
                    match_id
                ),
            )
            conn.commit()

def process_record(record: dict[str, Any]) -> None:
    body = json.loads(record["body"])
    match_id = body["match_id"]
    next_status = body["status"]
    reason = body.get("reason")
    duration_sec = body.get("duration_sec")

    update_status(
        match_id=match_id,
        next_status=next_status,
        reason=reason,
        duration_sec=duration_sec
    )
    logger.info("Updated match_id=%s to %s", match_id, next_status)

def handler(event: dict[str, Any], context: Any) -> dict[str, int]:
    logger.info("Received event: %s", json.dumps(event))

    processed = 0
    for record in event.get("Records", []):
        process_record(record)
        processed += 1

    return {"processed": processed}