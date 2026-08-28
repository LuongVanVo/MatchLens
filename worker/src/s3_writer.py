# Mục đích: upload raw clips và tracking batch JSON lên S3
from pathlib import Path
import json

import boto3

from .schemas import TrackingBatch


class S3Writer:
    def __init__(self, region_name: str) -> None:
        self.s3 = boto3.client("s3", region_name=region_name)

    def upload_raw_clip(
        self,
        *,
        bucket: str,
        key: str,
        local_file_path: str,
        content_type: str = "video/mp4",
    ) -> None:
        self.s3.upload_file(
            local_file_path,
            bucket,
            key,
            ExtraArgs={"ContentType": content_type},
        )

    def upload_tracking_batch(
        self,
        *,
        bucket: str,
        key: str,
        batch: TrackingBatch,
    ) -> None:
        self.s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(batch.model_dump(mode="json")).encode("utf-8"),
            ContentType="application/json",
        )

    def download_file(
        self,
        *,
        bucket: str,
        key: str,
        local_file_path: str,
    ) -> None:
        Path(local_file_path).parent.mkdir(parents=True, exist_ok=True)
        self.s3.download_file(bucket, key, local_file_path)
