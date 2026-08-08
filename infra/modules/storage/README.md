# modules/storage

Phase 0: tạo 5 S3 bucket theo `docs/data-model.md` mục 3.2 — private hoàn toàn (block public access), versioning + SSE-S3 bật cho mọi bucket.

Lifecycle Phase 0:
- `raw-videos`: Glacier sau 30 ngày, xóa sau 90 ngày
- `raw-tracking-data`: Glacier sau 14 ngày (mốc tạm, Phase 6 đánh giá lại theo tốc độ Glue xử lý thật)
- `athena-results`: xóa vĩnh viễn sau 7 ngày
- `processed-highlights`, `curated-data`: chưa có lifecycle rule — bổ sung ở Phase 1 (CloudFront/OAC, prefix `raw-clips/` vs `clips/`)

`force_destroy = true` chỉ ở dev — cho phép `terraform destroy` xóa cả bucket có object, phục vụ mô hình apply-khi-làm/destroy-khi-nghỉ.

CloudFront + OAC + WAF + Signed URL key group: **không thuộc Phase 0**, xem `docs/roadmap.md` Phase 1.