# Mục đích: chứa hàm dùng chung, đặc biệt là deterministic event_id
import hashlib
from datetime import datetime, timezone
from pathlib import Path


def ensure_dir(path: str) -> None:
    Path(path).mkdir(parents=True, exist_ok=True)


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def to_iso8601_z(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def make_event_id(match_id: str, timestamp_in_video: float, event_type: str) -> str:
    ts_ms = int(timestamp_in_video * 1000)
    payload = f"{match_id}|{timestamp_in_video}|{event_type}"
    hash10 = hashlib.sha256(payload.encode()).hexdigest()[:10]
    return f"{ts_ms:013d}-{hash10}"
