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

### 2. VPC — Kiến trúc 3-Tier (2 Availability Zones)

> Quyết định Q1 (`docs/decision-record.md`): bắt buộc 3 tier, RDS cô lập hoàn toàn khỏi internet.

| Tier | Resource | Route ra internet |
|---|---|---|
| **Public Subnet** (mỗi AZ) | ALB (trải cả 2 AZ), NAT Instance | Qua Internet Gateway |
| **Private App Subnet** (mỗi AZ) | ECS Fargate — Backend API Service (NestJS + pnpm)<br>ECS Fargate — AI Worker Service (YOLOv11 inference)<br>Lambda `status-updater-fn` (cần RDS access) | Outbound-only qua NAT Instance |
| **Private DB Subnet** (mỗi AZ) | RDS PostgreSQL Master + Standby + Read Replica | **Không có route `0.0.0.0/0`** — cô lập tuyệt đối |

**Số lượng NAT Instance theo môi trường** (quyết định Q2):

| Environment | NAT Instance | Ghi chú |
|---|---|---|
| `dev` | **1** (Public Subnet AZ-A) | Private subnet AZ-B route cross-AZ về NAT ở AZ-A. Chấp nhận single point of failure để tiết kiệm chi phí |
| `staging` / `prod` | **2** (1 per AZ) | HA thật, mỗi AZ có route table riêng trỏ NAT cùng AZ |

**VPC Gateway Endpoint** (quyết định Q29 — triển khai ngay Phase 0): Gateway Endpoint cho **S3** và **DynamoDB** (miễn phí), gắn vào route table của Private App Subnet. Traffic ECS → S3 (hàng GB video) và ECS → DynamoDB không đi qua NAT Instance — vừa tiết kiệm data transfer, vừa không ra internet. Lưu ý: Secrets Manager không có Gateway Endpoint (chỉ Interface Endpoint ~$7/AZ/tháng), nên ở `dev` traffic tới Secrets Manager vẫn đi qua NAT.

**RDS PostgreSQL:** Master + Standby (Multi-AZ, tự động failover) + Read Replica riêng (async replication) để tách traffic đọc tải lớn (danh sách team/match/player) khỏi Master. Read Replica **không** phục vụ dữ liệu phân tích chỉ số cầu thủ (phần đó đi qua Athena/QuickSight, xem mục Data & Analytics Pipeline). Chi tiết: `docs/data-model.md` mục 1.1.1.

**Read Replica chỉ deploy ở `staging`/`prod`** (quyết định Q3) — ở `dev`, cả 2 biến `DATABASE_URL_MASTER` và `DATABASE_URL_REPLICA` trỏ cùng endpoint Master để tiết kiệm ~$14/tháng. Code Backend không đổi giữa các môi trường.

### 3. Async Processing Pipeline
- User upload video trực tiếp lên **S3 (raw-videos)** qua presigned URL do Backend cấp
- S3 Event Notification → **Lambda (Job Dispatcher)** → **SQS Queue (video-processing-jobs)**
- **AI Worker Service** poll SQS, xử lý video, ghi kết quả ra:
  - S3 (processed-highlights), prefix `raw-clips/` — clip thô đã cắt
  - DynamoDB (detection metadata) — dữ liệu sự kiện
  - S3 (raw-tracking-data) — dữ liệu tracking thô
- Worker ghi clip vào prefix `raw-clips/` → S3 Event (filter prefix `raw-clips/`) → **Lambda `mediaconvert-trigger-fn`** → **AWS MediaConvert** transcode, ghi output sang prefix `clips/` cùng bucket (quyết định Q19b/Q21 — tách 2 prefix để chống vòng lặp S3 Event đệ quy; Worker **không** gọi MediaConvert trực tiếp)
- Job lỗi sau nhiều lần retry → **SQS Dead Letter Queue (DLQ)**

### 3.1. Status Callback Pipeline (quyết định Q20)

Worker và Job Dispatcher **không có RDS credential**. Việc cập nhật `matches.status` đi qua đường riêng:

```
Job Dispatcher ─┐
                ├─→ SQS matchlens-{env}-match-status-callbacks ─→ Lambda status-updater-fn ─→ RDS
AI Worker ──────┘                    │
                                     └─→ DLQ + CloudWatch Alarm (nếu Lambda fail)
```

`status-updater-fn` là **thành phần compute duy nhất ngoài Backend API có quyền ghi RDS**, đặt trong Private App Subnet. Backend vẫn tự ghi trực tiếp 2 trạng thái đầu (`pending`, `uploaded`) để phản hồi tức thì cho UI.

### 4. Data & Analytics Pipeline
- S3 (raw-tracking-data) → **AWS Glue ETL Job** → S3 (curated-data, Parquet, Hive-style partition `team_id=.../match_id=...`)
- **Glue Data Catalog** quản lý schema
- **Amazon Athena** truy vấn SQL trên curated data, ghi kết quả vào bucket riêng **S3 (athena-results)** — lifecycle xoá sau 7 ngày (quyết định Q30)
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
2. **Worker không expose ra internet** — chỉ chạy trong Private App Subnet, nhận job qua SQS
3. **CloudFront chỉ có 1 distribution** — 2 origin khác nhau cho app traffic và video content, không tạo 2 CloudFront riêng
4. **RDS không public accessible** — đặt trong Private DB Subnet không có route ra internet, chỉ Security Group của ECS service và `status-updater-fn` được phép kết nối
5. **NAT Instance, không phải NAT Gateway** — quyết định tối ưu chi phí đã chốt (xem `docs/cost-estimate.md`)
6. **Mọi resource đều phải có tag chuẩn và tên theo convention** — xem `docs/naming-tagging-standard.md` trước khi đặt tên bất kỳ resource nào
7. **Chỉ 2 thành phần được ghi RDS**: Backend API Service và `status-updater-fn`. Worker, Job Dispatcher, MediaConvert trigger Lambda tuyệt đối không có RDS credential (quyết định Q20)
8. **S3 processed-highlights tách 2 prefix** `raw-clips/` (input) và `clips/` (output MediaConvert) — S3 Event filter theo `raw-clips/` để chống vòng lặp đệ quy (quyết định Q19b)
9. **Bucket processed-highlights là private hoàn toàn** — chỉ CloudFront truy cập qua OAC, client nhận CloudFront Signed URL hiệu lực 4 giờ (quyết định Q23)
10. **Toàn bộ quyết định kiến trúc đã chốt nằm ở `docs/decision-record.md`** — đọc file đó khi có bất kỳ điểm mâu thuẫn giữa các tài liệu

---

## File sơ đồ hình ảnh

Đặt file ảnh sơ đồ kiến trúc đã duyệt (bản cuối cùng, đã qua các vòng review) tại:
```
diagrams/MatchLens - Football Analytics Platform.drawio.png
```

