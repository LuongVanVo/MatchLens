$buckets = @(
    "matchlens-dev-raw-videos",
    "matchlens-dev-processed-highlights",
    "matchlens-dev-raw-tracking-data",
    "matchlens-dev-curated-data",
    "matchlens-dev-athena-results"
)

Write-Host "Bat dau keo du lieu tu tat ca cac s3 buckets ve may..." -ForegroundColor Cyan

foreach ($bucket in $buckets) {
    Write-Host "Dang backup: $bucket" -ForegroundColor Yellow
    aws s3 sync "s3://$bucket" "./s3-backup/$bucket"
}

Write-Host "Backup toan bo S3 hoan tat!" -ForegroundColor Green