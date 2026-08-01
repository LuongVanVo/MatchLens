# MatchLens — Infrastructure Architecture

> Mô tả kiến trúc hạ tầng dạng text để công cụ AI (Claude Code) có thể đọc và hiểu được toàn bộ hệ thống. Sơ đồ hình ảnh trực quan nên được đặt tại `diagrams/MatchLens - Football Analytics Platform.drawio.png` (xuất từ bản thiết kế đã duyệt) để tham chiếu khi cần trình bày.

---

## Tổng quan

MatchLens là nền tảng phân tích trận đấu bóng đá: cắt highlight tự động bằng AI (YOLOv11) và phân tích chỉ số cầu thủ. Hạ tầng triển khai trên AWS, IaC bằng Terraform.

## Kiến trúc theo layer

### 1. Client & CDN Layer
- **Route 53**: DNS
- **CloudFront**: CDN, 1 distribution với 2 origin — Origin 1 (ALB, app traffic), Origin 2 (S3 processed-highlights, video content)
- **WAF**: gắn vào CloudFront

### 2. VPC (2 Availability Zones)
- **ALB**: đặt trong VPC (Public Subnet, trải cả 2 AZ), route traffic vào ECS Backend API Service
- **Public Subnet** (mỗi AZ): NAT Instance
- **Private Subnet** (mỗi AZ):
  - ECS Fargate — Backend API Service (NestJS (với pnpm))
  - ECS Fargate — AI Worker Service (YOLOv11 inference)
- **RDS PostgreSQL (Multi-AZ) + Read Replica**: Master/Standby (Multi-AZ, tự động failover) đặt cùng AZ layout, cộng thêm 1 Read Replica riêng (async replication) để tách traffic đọc tải lớn (danh sách team/match/player) khỏi Master — không phục vụ dữ liệu phân tích chỉ số cầu thủ (phần đó đi qua Athena/QuickSight, xem mục Data & Analytics Pipeline). Chi tiết: `docs/data-model.md` mục 1.1.1

### 3. Async Processing Pipeline
- User upload video trực tiếp lên **S3 (raw-videos)** qua presigned URL do Backend cấp
- S3 Event Notification → **Lambda (Job Dispatcher)** → **SQS Queue (video-processing-jobs)**
- **AI Worker Service** poll SQS, xử lý video, ghi kết quả ra:
  - S3 (processed-highlights) — clip đã cắt
  - DynamoDB (detection metadata) — dữ liệu sự kiện
  - S3 (raw-tracking-data) — dữ liệu tracking thô
- **AWS MediaConvert** transcode clip trong S3 processed-highlights
- Job lỗi sau nhiều lần retry → **SQS Dead Letter Queue (DLQ)**

### 4. Data & Analytics Pipeline
- S3 (raw-tracking-data) → **AWS Glue ETL Job** → S3 (curated-data, Parquet)
- **Glue Data Catalog** quản lý schema
- **Amazon Athena** truy vấn SQL trên curated data
- **QuickSight Dashboard** trực quan hóa (heatmap, so sánh chỉ số)

### 5. Cross-cutting: Security & Governance
IAM, Secrets Manager, Security Hub, AWS Config, GuardDuty — áp dụng cho toàn bộ hệ thống (chi tiết: `docs/iam-security-design.md`)

### 6. CI/CD Pipeline
GitHub Actions → Amazon ECR → ECS Services (Backend & Worker). Build → Scan (Trivy) → Push → Deploy. (chi tiết: `docs/cicd-design.md`)

### 7. Observability
CloudWatch (Dashboard + Alarms) → SNS → Email/Slack (chi tiết trong `docs/system-flows.md` mục 6)

---

## Nguyên tắc kiến trúc quan trọng (Claude Code cần tuân thủ khi code)

1. **User không upload video qua Backend** — chỉ qua presigned URL thẳng lên S3, Backend chỉ cấp URL
2. **Worker không expose ra internet** — chỉ chạy trong Private Subnet, nhận job qua SQS
3. **CloudFront chỉ có 1 distribution** — 2 origin khác nhau cho app traffic và video content, không tạo 2 CloudFront riêng
4. **RDS không public accessible** — chỉ Security Group của ECS service được phép kết nối
5. **NAT Instance, không phải NAT Gateway** — quyết định tối ưu chi phí đã chốt (xem `docs/cost-estimate.md`)
6. **Mọi resource đều phải có tag chuẩn và tên theo convention** — xem `docs/naming-tagging-standard.md` trước khi đặt tên bất kỳ resource nào

---

## File sơ đồ hình ảnh

Đặt file ảnh sơ đồ kiến trúc đã duyệt (bản cuối cùng, đã qua các vòng review) tại:
```
diagrams/MatchLens - Football Analytics Platform.drawio.png
```

