# Mục đích: Gửi callback vào queue match-status-callbacks

import json
from datetime import datetime, timezone

import boto3

from .schemas import StatusCallbackMessage


class StatusNotifier:
    def __init__(self, queue_url: str, region_name: str) -> None:
        self.queue_url = queue_url
        self.sqs = boto3.client("sqs", region_name=region_name)

    def send(
        self,
        *,
        match_id: str,
        status: str,
        reason: str | None = None,
        duration_sec: int | None = None,
        emitted_at: datetime | None = None,
    ) -> None:
        payload = StatusCallbackMessage(
            match_id=match_id,
            status=status,
            reason=reason,
            duration_sec=duration_sec,
            emitted_at=emitted_at or datetime.now(timezone.utc),
        )

        self.sqs.send_message(
            QueueUrl=self.queue_url,
            MessageBody=json.dumps(payload.model_dump(mode="json")),
        )
