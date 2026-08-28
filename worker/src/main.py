# Mục đích: entrypoint poll SQS, orchestration toàn flow

import logging
import os
import shutil
import traceback

import boto3

from .config import Settings
from .db_writer import MatchEventsWriter
from .detector import VideoDetector
from .s3_writer import S3Writer
from .schemas import VideoProcessingJob
from .status_notifier import StatusNotifier
from .utils import ensure_dir

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_local_paths(settings: Settings, match_id: str) -> dict[str, str]:
    base_dir = os.path.join(settings.local_workspace_dir, match_id)
    input_video = os.path.join(base_dir, "original.mp4")
    ensure_dir(base_dir)
    return {
        "base_dir": base_dir,
        "input_video": input_video,
    }


def process_message(
    *,
    settings: Settings,
    sqs_client,
    receipt_handle: str,
    message_body: str,
) -> None:
    job = VideoProcessingJob.model_validate_json(message_body)
    logger.info("Processing match_id=%s", job.match_id)

    db_writer = MatchEventsWriter(settings.match_events_table_name, settings.aws_region)
    if db_writer.has_completed_marker(job.match_id):
        logger.info("Skip match_id=%s because completed marker already exists.", job.match_id)
        delete_message(sqs_client, settings.video_processing_queue_url, receipt_handle)
        return

    s3_writer = S3Writer(settings.aws_region)
    notifier = StatusNotifier(settings.status_callbacks_queue_url, settings.aws_region)
    detector = VideoDetector(
        model_path=settings.model_path,
        tracker_type=settings.tracker_type,
        schema_version=settings.schema_version,
    )

    paths = build_local_paths(settings, job.match_id)

    try:
        notifier.send(
            match_id=job.match_id,
            status="processing",
        )

        s3_writer.download_file(
            bucket=job.s3_bucket,
            key=job.s3_key,
            local_file_path=paths["input_video"],
        )

        result = detector.process_video(
            local_video_path=paths["input_video"],
            match_id=job.match_id,
            team_id=job.team_id,
            tracking_batch_size=settings.tracking_batch_size,
            workspace_dir=paths["base_dir"],
        )

        logger.info(
            "Detection complete: %d events, %d clips, %d tracking batches",
            len(result.events),
            len(result.clips),
            len(result.tracking_batches),
        )

        for batch in result.tracking_batches:
            tracking_key = f"{job.team_id}/{job.match_id}/tracking_batch_{batch.batch_number}.json"
            s3_writer.upload_tracking_batch(
                bucket=settings.raw_tracking_data_bucket_name,
                key=tracking_key,
                batch=batch,
            )

        for clip in result.clips:
            s3_writer.upload_raw_clip(
                bucket=settings.processed_highlights_bucket_name,
                key=clip.raw_clip_s3_key,
                local_file_path=clip.local_clip_path,
            )

        if result.events:
            db_writer.put_events(result.events)

        db_writer.put_completed_marker(job.match_id)

        notifier.send(
            match_id=job.match_id,
            status="completed",
            duration_sec=result.duration_sec,
        )

        delete_message(sqs_client, settings.video_processing_queue_url, receipt_handle)

    except Exception as exc:
        logger.exception("Worker failed for match_id=%s", job.match_id)
        notifier.send(
            match_id=job.match_id,
            status="failed",
            reason=str(exc),
        )
        raise
    finally:
        shutil.rmtree(paths["base_dir"], ignore_errors=True)


def delete_message(sqs_client, queue_url: str, receipt_handle: str) -> None:
    sqs_client.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)


def main() -> None:
    settings = Settings.from_env()
    ensure_dir(settings.local_workspace_dir)

    sqs_client = boto3.client("sqs", region_name=settings.aws_region)

    while True:
        response = sqs_client.receive_message(
            QueueUrl=settings.video_processing_queue_url,
            MaxNumberOfMessages=settings.sqs_max_messages,
            WaitTimeSeconds=settings.sqs_wait_time_seconds,
        )

        messages = response.get("Messages", [])
        if not messages:
            continue

        for message in messages:
            receipt_handle = message["ReceiptHandle"]
            body = message["Body"]

            try:
                process_message(
                    settings=settings,
                    sqs_client=sqs_client,
                    receipt_handle=receipt_handle,
                    message_body=body,
                )
            except Exception:
                logger.error(traceback.format_exc())
                # Không delete message; để SQS retry / DLQ xử lý


if __name__ == "__main__":
    main()
