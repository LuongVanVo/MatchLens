# Mục đích: Gom validate toàn bộ env vars cho worker

from dataclasses import dataclass
import os

def _get_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value

def _get_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if not value:
        return default
    return int(value)

@dataclass(frozen=True)
class Settings:
    aws_region: str
    video_processing_queue_url: str
    status_callbacks_queue_url: str
    raw_videos_bucket_name: str
    processed_highlights_bucket_name: str
    raw_tracking_data_bucket_name: str
    match_events_table_name: str
    sqs_wait_time_seconds: int
    sqs_max_messages: int
    tracking_batch_size: int
    local_workspace_dir: str
    model_path: str
    tracker_type: str
    schema_version: int

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            aws_region=_get_env("AWS_REGION"),
            video_processing_queue_url=_get_env("VIDEO_PROCESSING_QUEUE_URL"),
            status_callbacks_queue_url=_get_env("STATUS_CALLBACKS_QUEUE_URL"),
            raw_videos_bucket_name=_get_env("RAW_VIDEOS_BUCKET_NAME"),
            processed_highlights_bucket_name=_get_env("PROCESSED_HIGHLIGHTS_BUCKET_NAME"),
            raw_tracking_data_bucket_name=_get_env("RAW_TRACKING_DATA_BUCKET_NAME"),
            match_events_table_name=_get_env("MATCH_EVENTS_TABLE_NAME"),
            sqs_wait_time_seconds=_get_int("SQS_WAIT_TIME_SECONDS", 20),
            sqs_max_messages=_get_int("SQS_MAX_MESSAGES", 1),
            tracking_batch_size=_get_int("TRACKING_BATCH_SIZE", 250),
            local_workspace_dir=os.getenv("LOCAL_WORKSPACE_DIR", "/tmp/matchlens-worker"),
            model_path=os.getenv("MODEL_PATH", "/app/models/yolo11n.pt"),
            tracker_type=os.getenv("TRACKER_TYPE", "bytetrack"),
            schema_version=_get_int("SCHEMA_VERSION", 1),
        )