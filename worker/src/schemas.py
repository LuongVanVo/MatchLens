# Mục đích: define contract bằng pydantic để validate trước khi ghi ra S3/DynamoDB/SQS

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class VideoProcessingJob(BaseModel):
    model_config = ConfigDict(extra="forbid")

    match_id: str
    team_id: str
    s3_bucket: str
    s3_key: str
    uploaded_at: datetime


class StatusCallbackMessage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    match_id: str
    status: Literal["processing", "completed", "failed"]
    reason: str | None = None
    duration_sec: int | None = None
    emitted_at: datetime


class FieldDimensions(BaseModel):
    model_config = ConfigDict(extra="forbid")

    length_m: float = 105.0
    width_m: float = 68.0


class BBox(BaseModel):
    model_config = ConfigDict(extra="forbid")

    x: float
    y: float
    width: float
    height: float


class Point(BaseModel):
    model_config = ConfigDict(extra="forbid")

    x: float
    y: float

class BallPosition(BaseModel):
    model_config = ConfigDict(extra="forbid")

    x: float
    y: float
    confidence: float


class TrackingFrameObject(BaseModel):
    model_config = ConfigDict(extra="forbid")

    track_id: int
    player_id: str | None = None
    jersey_number: int | None = None
    class_name: Literal["player", "ball", "referee", "goalkeeper"]
    confidence: float
    bbox: BBox
    position_field: Point
    team_side: Literal["home", "away", "unknown"]


class TrackingFrame(BaseModel):
    model_config = ConfigDict(extra="forbid")

    frame: int
    timestamp_sec: float
    detections: list[TrackingFrameObject]
    ball_position: BallPosition | None = None


class TrackingBatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: int
    match_id: str
    batch_number: int
    frame_rate: int
    field_dimensions: FieldDimensions
    frames: list[TrackingFrame]


EventType = Literal["shot", "foul", "fast_break", "goal", "corner_kick"]


class MatchEventItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    match_id: str
    event_id: str
    event_type: EventType
    timestamp_in_video: float
    highlight_clip_s3_key: str
    confidence_score: float
    track_ids_involved: list[int] = Field(default_factory=list)
    created_at: datetime


class CompletedMarkerItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    match_id: str
    event_id: Literal["MARKER#COMPLETED"]
    created_at: datetime
