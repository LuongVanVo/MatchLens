# Mục đích: Ghi event items và marker vào DynamoDB

from datetime import datetime, timezone
from .schemas import CompletedMarkerItem
from .schemas import MatchEventItem
from typing import Iterable
import boto3

class MatchEventsWriter:
    def __init__(self, table_name: str, region_name: str) -> None:
        dynamodb = boto3.resource("dynamodb", region_name=region_name)
        self.table = dynamodb.Table(table_name)

    def has_completed_marker(self, match_id: str) -> bool:
        response = self.table.get_item(
            Key={
                "match_id": match_id,
                "event_id": "MARKER#COMPLETED"
            },
            ConsistentRead=True,
        )
        return "Item" in response
    
    def put_events(self, events: Iterable[MatchEventItem]) -> None:
        with self.table.batch_writer() as batch:
            for event in events:
                batch.put_item(Item=event.model_dump(mode="json"))

    def put_completed_marker(self, match_id: str) -> None:
        marker = CompletedMarkerItem(
            match_id=match_id,
            event_id="MARKER#COMPLETED",
            created_at=datetime.now(timezone.utc),
        )
        self.table.put_item(
            Item=marker.model_dump(mode="json"),
            ConditionExpression="attribute_not_exists(match_id) AND attribute_not_exists(event_id)",
        )