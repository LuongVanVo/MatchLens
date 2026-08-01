# MatchLens — Roadmap Triển Khai Chi Tiết

> Mở rộng chi tiết từ bảng Phase tóm tắt ở `CLAUDE.md` mục 6. File này là nguồn tham chiếu chính khi làm việc với Claude Code để biết chính xác từng Phase cần làm gì, khi nào coi là xong, và phụ thuộc Phase nào trước. Không chia cứng theo tuần vì mỗi Phase có độ dài khác nhau.

---

## Nguyên tắc chung

- Ưu tiên có sản phẩm chạy được và demo được sớm — Phase 0 và Phase 1 làm trước tiên vì đây là phần lõi
- Các Phase Security/CI-CD/Observability/DR (2-5) có thể triển khai xen kẽ sau khi hạ tầng core đã ổn định, không bắt buộc phải làm tuần tự cứng nhắc
- Phase 6 (Analytics) chỉ bắt đầu sau khi Phase 0-5 chạy ổn định — tránh mở rộng tính năng khi nền tảng chưa vững
- Sau khi hoàn thành 1 Phase, cập nhật trạng thái ở bảng tại `CLAUDE.md` mục 6 VÀ tick vào checklist deliverable tương ứng trong file này

---

## Phase 0 — Nền tảng ứng dụng cơ bản

**Mục tiêu:** Có một web app chạy được trên AWS, dù chưa có AI, để làm nền cho toàn bộ các Phase sau.

### Task cụ thể
- [ ] `infra/global/bootstrap/`: tạo S3 backend + DynamoDB lock table
- [ ] `infra/modules/network/`: VPC 2AZ theo kiến trúc 3-Tier (Public Subnet, Private App Subnet, Private DB Subnet), 1 NAT Instance (AZ-A, dùng chung cross-AZ), Internet Gateway
- [ ] `infra/modules/database/`: RDS PostgreSQL Master + Standby (Multi-AZ ở prod, Single-AZ ở dev) + Read Replica, theo đúng `docs/database-schema.md`
- [ ] `infra/modules/compute/`: ECS Cluster, ALB, Task Definition + Service cho Backend API (chưa cần Worker ở Phase này)
- [ ] `backend/`: khởi tạo dự án NestJS + pnpm, cấu hình Prisma với 2 datasource (write/read) theo `docs/backend-architecture.md`
- [ ] Code Prisma schema + migration đầu tiên theo đúng `docs/database-schema.md`
- [ ] Code các endpoint CRUD cơ bản: `auth`, `teams`, `players`, `matches` (chưa cần `upload-url`, `highlights`, `stats`) theo `docs/api-design.md`
- [ ] Thêm `HealthModule` (`/health`) để ECS/ALB Health Check dùng — đã ghi chú ở `docs/backend-architecture.md` mục 9
- [ ] `frontend/`: khởi tạo React + Vite, trang đăng nhập, tạo team, danh sách trận đấu (form cơ bản, chưa cần upload video thật)

### Deliverable — Phase 0 coi là xong khi
- Có thể đăng ký/đăng nhập, tạo team, thêm player, tạo match (chưa có video) qua giao diện web thật, chạy trên AWS (không phải chỉ chạy local)
- ALB Health Check pass, ECS Service ổn định

### Phụ thuộc
- Không phụ thuộc Phase nào khác — làm đầu tiên

---

## Phase 1 — Highlight Engine

**Mục tiêu:** Tính năng lõi hoạt động — upload video, AI xử lý, trả về highlight tự động.

### Task cụ thể
- [ ] `infra/modules/storage/`: 4 S3 bucket (raw-videos, processed-highlights, raw-tracking-data, curated-data), lifecycle policy, CloudFront (2 Origin), WAF
- [ ] `infra/modules/messaging/`: SQS Queue + DLQ, Lambda Job Dispatcher, cấu hình S3 Event Notification
- [ ] `infra/modules/compute/`: bổ sung ECS Service cho AI Worker (chưa có ở Phase 0)
- [ ] `backend/`: code endpoint `POST /matches/{id}/upload-url`, `POST /matches/{id}/confirm-upload`, `GET /matches/{id}/status`, `GET /matches/{id}/highlights` theo `docs/api-design.md`
- [ ] `worker/`: khởi tạo dự án Python, code `main.py` (poll SQS), `detector.py` (YOLOv11 inference — dùng pretrained/dataset công khai cho football object detection, không tự train từ đầu ở bản đầu), `s3_writer.py`, `db_writer.py` theo đúng `docs/data-contracts.md`
- [ ] Cấu hình MediaConvert transcode job
- [ ] `frontend/`: trang upload video (dùng presigned URL), trang xem highlight (video player nhúng CloudFront URL), polling trạng thái xử lý

### Deliverable — Phase 1 coi là xong khi
- Upload được video thật qua giao diện, hệ thống tự động xử lý (không cần can thiệp thủ công), xem được ít nhất 1 highlight clip tự động cắt ra
- DLQ hoạt động đúng khi cố tình cho job lỗi (test thử 1 lần)

### Phụ thuộc
- Cần Phase 0 xong (đặc biệt: Backend, RDS, VPC đã có)

---

## Phase 2 — Security & Governance

**Mục tiêu:** Đưa hạ tầng về chuẩn least-privilege, có khả năng tự phát hiện lỗ hổng.

### Task cụ thể
- [ ] `infra/modules/security/`: toàn bộ IAM Role theo đúng ma trận ở `docs/iam-security-design.md` (Backend, Worker, Lambda Dispatcher, Glue, CI/CD role qua OIDC)
- [ ] Secrets Manager: DB credentials, JWT secret — Backend/Worker đọc qua đây, không hardcode
- [ ] Bật Security Hub, AWS Config (rule theo CIS Benchmark), GuardDuty
- [ ] Rà soát và khắc phục ít nhất 5 security finding thực tế, ghi lại before/after (dùng cho portfolio sau này)
- [ ] Cấu hình ACM cho HTTPS custom domain (nếu dùng domain riêng)

### Deliverable — Phase 2 coi là xong khi
- Không còn IAM Role nào dùng quyền wildcard `*` không cần thiết
- Security Hub có báo cáo compliance score, đã fix ít nhất 5 finding có bằng chứng before/after

### Phụ thuộc
- Cần Phase 0-1 xong (cần biết chính xác resource ARN để viết IAM Policy đúng)

---

## Phase 3 — CI/CD

**Mục tiêu:** Tự động hóa build – scan – deploy.

### Task cụ thể
- [ ] `.github/workflows/backend-cicd.yml`: lint, test, build, Trivy scan, push ECR, deploy 3 môi trường theo `docs/cicd-design.md`
- [ ] `.github/workflows/worker-cicd.yml`: tương tự cho Worker (Python)
- [ ] `.github/workflows/terraform-plan.yml`: tự động `terraform plan` khi có PR liên quan `infra/`
- [ ] Cấu hình GitHub Environment Protection Rule cho môi trường `production` (yêu cầu approval)
- [ ] Cấu hình OIDC Federation giữa GitHub Actions và AWS (không dùng access key tĩnh)

### Deliverable — Phase 3 coi là xong khi
- Push code lên nhánh `develop` tự động deploy `dev` thành công, không cần thao tác tay
- Deploy `prod` yêu cầu approval, đã test thử rollback về 1 revision cũ thành công

### Phụ thuộc
- Cần Phase 2 xong (IAM Role cho CI/CD đã có)

---

## Phase 4 — Observability

**Mục tiêu:** Có khả năng giám sát và phản ứng khi hệ thống gặp sự cố.

### Task cụ thể
- [ ] `infra/modules/observability/`: CloudWatch Dashboard, Alarm (SQS DLQ có message, ECS fail, RDS storage, ALB 5xx), SNS Topic
- [ ] Kết nối SNS với email/Slack
- [ ] Viết 2-3 runbook xử lý sự cố mẫu (lưu ở `docs/` hoặc `knowledge/`, ví dụ `knowledge/runbooks.md`)

### Deliverable — Phase 4 coi là xong khi
- Alarm thực sự bắn được thông báo (test thử bằng cách cố tình gây lỗi), có ít nhất 2 runbook cụ thể

### Phụ thuộc
- Cần Phase 1-3 xong (cần đủ resource để giám sát)

---

## Phase 5 — Reliability & Disaster Recovery

**Mục tiêu:** Chứng minh khả năng phục hồi sau sự cố bằng số liệu thật.

### Task cụ thể
- [ ] Test RDS Multi-AZ failover (ở môi trường staging/prod)
- [ ] Test restore từ snapshot, đo RTO thực tế
- [ ] Viết DR Plan ngắn gọn (`docs/` hoặc file riêng), có số liệu RTO/RPO đo được

### Deliverable — Phase 5 coi là xong khi
- Có bằng chứng (log/screenshot) đã test restore thành công, RTO đo được ghi rõ trong tài liệu

### Phụ thuộc
- Cần Phase 0 xong (cần RDS Multi-AZ đã chạy)

---

## Phase 6 — Performance Analytics (mở rộng v2)

**Mục tiêu:** Hoàn thiện module phân tích chỉ số cầu thủ, biến sản phẩm từ "công cụ cắt clip" thành "nền tảng phân tích chiến thuật".

### Task cụ thể
- [ ] `etl/player_stats_job.py`: đọc `knowledge/aws-glue.md` trước khi code, xử lý đúng theo schema ở `docs/data-contracts.md` mục 3-4
- [ ] Cấu hình Glue Crawler, Glue Data Catalog
- [ ] Cấu hình Athena Workgroup
- [ ] `backend/`: code endpoint `GET /matches/{id}/stats` — quyết định cache kết quả hay query Athena trực tiếp (câu hỏi mở ở `docs/api-design.md` mục 9, cần chốt trước khi code)
- [ ] QuickSight Dashboard hoặc dashboard tự build (Streamlit) — xem lại quyết định chi phí ở `docs/cost-estimate.md`
- [ ] `frontend/`: trang hiển thị heatmap, chỉ số cầu thủ

### Deliverable — Phase 6 coi là xong khi
- Xem được heatmap và chỉ số (quãng đường, tốc độ) của ít nhất 1 cầu thủ từ 1 trận đã xử lý xong

### Phụ thuộc
- Cần Phase 0-1 xong (cần dữ liệu tracking thô đã có trong S3 raw-tracking-data)
- Chỉ bắt đầu sau khi Phase 0-5 đã chạy ổn định, theo đúng nguyên tắc đã thống nhất trước đó (không mở rộng khi nền tảng core chưa vững)

---

## Phase 7 — Cost Optimization & Hoàn thiện Portfolio

**Mục tiêu:** Tối ưu chi phí, hoàn thiện tài liệu để sẵn sàng đưa vào CV.

### Task cụ thể
- [ ] Rà soát tag đầy đủ cho mọi resource theo `docs/naming-tagging-standard.md`
- [ ] Thiết lập AWS Budget Alert theo `docs/cost-estimate.md` mục 5
- [ ] Áp dụng các biện pháp tối ưu chi phí đã liệt kê (S3 Lifecycle, autoscale Worker về 0, v.v.)
- [ ] Cập nhật `README.md` hoàn chỉnh: giới thiệu, kiến trúc, hướng dẫn chạy, ảnh/video demo
- [ ] Viết case study ngắn (vấn đề — giải pháp — số liệu đo được) để dùng khi phỏng vấn

### Deliverable — Phase 7 coi là xong khi
- Chi phí thực tế theo dõi được qua Budget, có README đầy đủ, có ít nhất 1 video demo ngắn (2-3 phút)

### Phụ thuộc
- Làm sau cùng, sau khi các Phase khác đã ổn định

---

## Bảng tổng hợp phụ thuộc giữa các Phase

```
Phase 0 (nền tảng)
   │
   ├──> Phase 1 (Highlight Engine)
   │        │
   │        ├──> Phase 2 (Security) ──> Phase 3 (CI/CD) ──> Phase 4 (Observability)
   │        │
   │        └──> Phase 6 (Analytics, làm sau cùng cùng nhóm core)
   │
   └──> Phase 5 (Reliability/DR, chỉ cần Phase 0)

Phase 7 (Cost & Portfolio) — làm sau cùng, sau khi mọi Phase khác ổn định
```

---

## Việc cần làm khi cập nhật file này

Mỗi khi hoàn thành 1 task hoặc 1 Phase:
1. Tick checkbox tương ứng trong file này
2. Cập nhật trạng thái (⏳/✅) ở bảng Roadmap tại `CLAUDE.md` mục 6
3. Nếu phát sinh quyết định kỹ thuật mới trong quá trình code khác với thiết kế ban đầu, cập nhật lại đúng file `docs/` liên quan trước, không chỉ sửa code
