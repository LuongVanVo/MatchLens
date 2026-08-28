# Mục đích: Chạy YOLO + Tracker, trích events, cắt clips, build tracking batches

from dataclasses import dataclass
from pathlib import Path

import cv2
from ultralytics import YOLO

from .homography import HomographyProjector
from .event_analyzer import EventAnalyzer, FrameSnapshot
from .schemas import (
    BallPosition,
    BBox,
    FieldDimensions,
    MatchEventItem,
    Point,
    TrackingBatch,
    TrackingFrame,
    TrackingFrameObject,
)
from .utils import ensure_dir, make_event_id, utc_now


@dataclass
class DetectedClip:
    event_id: str
    event_type: str
    timestamp_in_video: float
    start_sec: float
    end_sec: float
    local_clip_path: str
    raw_clip_s3_key: str
    final_highlight_s3_key: str


@dataclass
class DetectionResult:
    events: list[MatchEventItem]
    clips: list[DetectedClip]
    tracking_batches: list[TrackingBatch]
    duration_sec: int


class VideoDetector:
    def __init__(self, model_path: str, tracker_type: str, schema_version: int) -> None:
        self.model = YOLO(model_path)
        self.tracker_type = tracker_type
        self.schema_version = schema_version

    def process_video(
        self,
        *,
        local_video_path: str,
        match_id: str,
        team_id: str,
        tracking_batch_size: int,
        workspace_dir: str,
        homography_projector: HomographyProjector | None = None,
    ) -> DetectionResult:
        capture = cv2.VideoCapture(local_video_path)
        fps = capture.get(cv2.CAP_PROP_FPS) or 25.0
        frame_rate = max(int(round(fps)), 1)
        frame_index = 0
        tracking_frames: list[TrackingFrame] = []
        frame_snapshots: list[FrameSnapshot] = []
        prev_gray = None

        try:
            while True:
                success, frame = capture.read()
                if not success:
                    break

                timestamp_sec = frame_index / fps

                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                motion_score = 0.0
                if prev_gray is not None:
                    diff = cv2.absdiff(prev_gray, gray)
                    motion_score = float(diff.mean())
                prev_gray = gray

                results = self.model.track(
                    source=frame,
                    persist=True,
                    tracker=f"{self.tracker_type}.yaml",
                    verbose=False,
                )

                detections: list[TrackingFrameObject] = []
                ball_position: Point | None = None
                ball_confidence = 0.0
                track_ids_involved: set[int] = set()
                has_ball = False
                player_count = 0

                for result in results:
                    boxes = getattr(result, "boxes", None)
                    if boxes is None:
                        continue

                    for box in boxes:
                        xyxy = box.xyxy[0].tolist()
                        cls_id = int(box.cls[0].item()) if box.cls is not None else -1
                        conf = float(box.conf[0].item()) if box.conf is not None else 0.0
                        track_id = int(box.id[0].item()) if box.id is not None else -1

                        center_x = (xyxy[0] + xyxy[2]) / 2
                        center_y = (xyxy[1] + xyxy[3]) / 2

                        if homography_projector is not None:
                            field_x, field_y = homography_projector.project(center_x, center_y)
                        else:
                            field_x = min(max((center_x / max(frame.shape[1], 1)) * 100.0, 0.0), 100.0)
                            field_y = min(max((center_y / max(frame.shape[0], 1)) * 100.0, 0.0), 100.0)

                        class_name = self._map_class_name(cls_id)
                        detections.append(
                            TrackingFrameObject(
                                track_id=track_id,
                                class_name=class_name,
                                confidence=conf,
                                bbox=BBox(
                                    x=float(xyxy[0]),
                                    y=float(xyxy[1]),
                                    width=float(xyxy[2] - xyxy[0]),
                                    height=float(xyxy[3] - xyxy[1]),
                                ),
                                position_field=Point(x=field_x, y=field_y),
                                team_side="unknown",
                            )
                        )

                        if track_id >= 0:
                            track_ids_involved.add(track_id)

                        if class_name == "ball":
                            has_ball = True
                            ball_confidence = max(ball_confidence, conf)
                            ball_position = Point(x=float(center_x), y=float(center_y))
                        elif class_name == "player":
                            player_count += 1

                frame_snapshots.append(
                    FrameSnapshot(
                        frame_index=frame_index,
                        timestamp_sec=timestamp_sec,
                        motion_score=motion_score,
                        has_ball=has_ball,
                        ball_confidence=ball_confidence,
                        ball_pixel_x=ball_position.x if ball_position else None,
                        ball_pixel_y=ball_position.y if ball_position else None,
                        ball_field_x=self._get_ball_field_x(homography_projector, ball_position, frame),
                        ball_field_y=self._get_ball_field_y(homography_projector, ball_position, frame),
                        player_count=player_count,
                        player_field_positions=[
                            (d.position_field.x, d.position_field.y)
                            for d in detections
                            if d.class_name == "player"
                        ],
                        track_ids=set(track_ids_involved),
                    )
                )

                tracking_frames.append(
                    TrackingFrame(
                        frame=frame_index,
                        timestamp_sec=round(timestamp_sec, 3),
                        detections=detections,
                        ball_position=BallPosition(
                            x=ball_position.x,
                            y=ball_position.y,
                            confidence=ball_confidence,
                        ) if ball_position else None,
                    )
                )

                frame_index += 1
        finally:
            capture.release()

        # Stage 2: Temporal event detection
        analyzer = EventAnalyzer()
        event_candidates = analyzer.analyze(frame_snapshots, match_id)

        # Build clips và events từ candidates
        clips: list[DetectedClip] = []
        events: list[MatchEventItem] = []
        for candidate in event_candidates:
            event_id = make_event_id(match_id, candidate.peak_timestamp_sec, candidate.event_type)
            local_clip_path = str(
                Path(workspace_dir)
                / "raw-clips"
                / team_id
                / match_id
                / f"{event_id}.mp4"
            )
            raw_clip_s3_key = f"raw-clips/{team_id}/{match_id}/{event_id}.mp4"
            final_highlight_s3_key = f"clips/{team_id}/{match_id}/{event_id}.mp4"

            clips.append(
                DetectedClip(
                    event_id=event_id,
                    event_type=candidate.event_type,
                    timestamp_in_video=candidate.peak_timestamp_sec,
                    start_sec=candidate.start_sec,
                    end_sec=candidate.end_sec,
                    local_clip_path=local_clip_path,
                    raw_clip_s3_key=raw_clip_s3_key,
                    final_highlight_s3_key=final_highlight_s3_key,
                )
            )
            events.append(
                MatchEventItem(
                    match_id=match_id,
                    event_id=event_id,
                    event_type=candidate.event_type,
                    timestamp_in_video=candidate.peak_timestamp_sec,
                    highlight_clip_s3_key=final_highlight_s3_key,
                    confidence_score=candidate.confidence,
                    track_ids_involved=candidate.track_ids_involved,
                    created_at=utc_now(),
                )
            )

        tracking_batches = self._build_tracking_batches(
            match_id=match_id,
            tracking_frames=tracking_frames,
            tracking_batch_size=tracking_batch_size,
            frame_rate=frame_rate,
        )

        duration_sec = int(frame_index / fps) if fps > 0 else 0
        for clip in clips:
            ensure_dir(str(Path(clip.local_clip_path).parent))
            self.export_clip(
                source_video_path=local_video_path,
                output_clip_path=clip.local_clip_path,
                start_sec=clip.start_sec,
                end_sec=min(clip.end_sec, duration_sec),
            )

        return DetectionResult(
            events=events,
            clips=clips,
            tracking_batches=tracking_batches,
            duration_sec=duration_sec,
        )

    def _get_ball_field_x(
        self,
        projector: HomographyProjector | None,
        ball_position: Point | None,
        frame,
    ) -> float | None:
        if ball_position is None:
            return None
        if projector is not None:
            fx, _ = projector.project(ball_position.x, ball_position.y)
            return fx
        return min(max((ball_position.x / max(frame.shape[1], 1)) * 100.0, 0.0), 100.0)

    def _get_ball_field_y(
        self,
        projector: HomographyProjector | None,
        ball_position: Point | None,
        frame,
    ) -> float | None:
        if ball_position is None:
            return None
        if projector is not None:
            _, fy = projector.project(ball_position.x, ball_position.y)
            return fy
        return min(max((ball_position.y / max(frame.shape[0], 1)) * 100.0, 0.0), 100.0)

    def _build_tracking_batches(
        self,
        *,
        match_id: str,
        tracking_frames: list[TrackingFrame],
        tracking_batch_size: int,
        frame_rate: int,
    ) -> list[TrackingBatch]:
        batches: list[TrackingBatch] = []
        for start in range(0, len(tracking_frames), tracking_batch_size):
            chunk = tracking_frames[start : start + tracking_batch_size]
            batch_number = (start // tracking_batch_size) + 1
            batches.append(
                TrackingBatch(
                    schema_version=self.schema_version,
                    match_id=match_id,
                    batch_number=batch_number,
                    frame_rate=frame_rate,
                    field_dimensions=FieldDimensions(),
                    frames=chunk,
                )
            )
        return batches

    def _map_class_name(self, cls_id: int) -> str:
        mapping = {
            0: "player",
            1: "ball",
            2: "referee",
            3: "goalkeeper",
        }
        return mapping.get(cls_id, "player")

    def export_clip(
        self,
        *,
        source_video_path: str,
        output_clip_path: str,
        start_sec: float,
        end_sec: float,
    ) -> None:
        capture = cv2.VideoCapture(source_video_path)
        fps = capture.get(cv2.CAP_PROP_FPS) or 25.0
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
        ensure_dir(str(Path(output_clip_path).parent))
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        writer = cv2.VideoWriter(output_clip_path, fourcc, fps, (width, height))

        try:
            start_frame = max(int(start_sec * fps), 0)
            end_frame = max(int(end_sec * fps), start_frame)
            capture.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

            current_frame = start_frame
            while current_frame <= end_frame:
                success, frame = capture.read()
                if not success:
                    break
                writer.write(frame)
                current_frame += 1
        finally:
            writer.release()
            capture.release()
