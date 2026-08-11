$buckets = @(
    "matchlens-dev-raw-videos",
    "matchlens-dev-processed-highlights",
    "matchlens-dev-raw-tracking-data",
    "matchlens-dev-curated-data",
    "matchlens-dev-athena-results"
)

Write-Host "Bat dau lay du lieu tu may len tat ca cac S3 Bucket..." -ForegroundColor Cyan

foreach ($bucket in $buckets) {
    if (Test-Path "./s3-backup/$bucket") {
        Write-Host "Dang restore: $bucket" -ForegroundColor Yellow
        aws s3 sync "./s3-backup/$bucket" "s3://$bucket"
    } else {
        Write-Host "Bo qua $bucket (khong co du lieu backup)" -ForegroundColor DarkGray
    }
}

Write-Host "Restore toan bo S3 hoan tat" -ForegroundColor Green