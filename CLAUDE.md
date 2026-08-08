# CLAUDE.md

> File này được Claude Code tự động đọc khi khởi động trong thư mục dự án. Cung cấp ngữ cảnh đầy đủ để triển khai chính xác theo đúng thiết kế đã chốt — không tự ý thay đổi kiến trúc/quyết định thiết kế đã ghi trong `docs/` mà không hỏi lại người dùng trước.

---

## 1. Tổng quan dự án

**Tên dự án:** MatchLens
**Mục đích:** Nền tảng phân tích trận đấu bóng đá — tự động cắt highlight bằng AI (YOLOv11) và phân tích chỉ số cầu thủ (heatmap, quãng đường di chuyển, tốc độ), giúp huấn luyện viên chuẩn bị chiến thuật cho trận tiếp theo.

**Bối cảnh sử dụng:** Đây là dự án cá nhân xây dựng để làm portfolio ứng tuyển vị trí Backend Developer / DevOps / Infrastructure Engineer. Mục tiêu không chỉ là "chạy được" mà phải thể hiện đúng chuẩn hạ tầng production-ready mà doanh nghiệp thực tế yêu cầu: IaC, Security & Governance, CI/CD, Observability, Reliability/DR, Cost Optimization.

**Phạm vi hiện tại (đang triển khai):** Tính năng lõi theo từng trận đấu — upload video, cắt highlight tự động, phân tích chỉ số trong phạm vi 1 trận. **Chưa** triển khai tính năng tổng hợp nhiều trận/mùa giải (để sau khi phần lõi chạy ổn định).

---

## 2. QUY TẮC QUAN TRỌNG VỀ QUYỀN HẠN THAO TÁC — ÁP DỤNG XUYÊN SUỐT DỰ ÁN

Đây là quy tắc bắt buộc, áp dụng cho **mọi phiên làm việc**, không chỉ phiên đầu tiên.

Mặc định, Claude Code **KHÔNG được** tự động tạo file, ghi đè file, hoặc chạy các lệnh làm thay đổi trạng thái máy hoặc hạ tầng AWS (bao gồm nhưng không giới hạn: `terraform apply`, `terraform destroy`, `git push`, `git commit`, cài đặt package thực thi thay đổi, `docker build`/`docker push`, deploy lên AWS, tạo/sửa/xóa resource AWS qua CLI) mà không có sự cho phép rõ ràng của người dùng trong từng lần cụ thể.

**Cách làm việc mặc định:**
1. Đề xuất code cụ thể (nội dung đầy đủ), nêu rõ: file này nên đặt ở đường dẫn nào, thao tác là tạo mới hay chỉnh sửa file đã có
2. Giải thích ngắn gọn code đó làm gì, vì sao viết như vậy, liên kết tới tài liệu thiết kế nào trong `docs/`
3. Hướng dẫn người dùng từng bước cụ thể để tự tay tạo/dán/chạy — không tự ý thực thi thay
4. Chỉ khi người dùng nói rõ ràng ("bạn tự tạo file này giúp tôi", "bạn chạy lệnh này giúp tôi") hoặc bật chế độ cho phép tự động, mới được tự thực hiện trực tiếp

**Về việc hỏi lại:** nếu có bất kỳ điểm nào chưa rõ, mơ hồ, mâu thuẫn giữa các tài liệu, hoặc cần quyết định thay người dùng (kể cả việc nhỏ như đặt tên biến, chọn giá trị mặc định), PHẢI dừng lại và hỏi trước — không tự suy đoán rồi tiến hành.

---

## 3. Toàn bộ tài liệu thiết kế đã chốt — LUÔN ĐỌC TRƯỚC KHI CODE

Mọi quyết định kiến trúc, schema, API, IAM, naming đã được thiết kế đầy đủ và chốt trong thư mục `docs/` (cấu trúc phẳng, không có thư mục con). Claude Code PHẢI đọc các file này trước khi tạo bất kỳ code/resource nào, và tuân thủ đúng theo đó. Đọc theo đúng thứ tự sau (file sau phụ thuộc vào hiểu biết từ file trước):

| Thứ tự | File | Nội dung |
|---|---|---|
| **0** | **`docs/decision-record.md`** | **⭐ ĐỌC TRƯỚC TIÊN — Architectural Decision Record (ADR): toàn bộ 34 quyết định đã chốt (Q1–Q34) + 5 quyết định hệ quả (D1–D5). Đây là NGUỒN CHÂN LÝ. Khi bất kỳ file nào khác mâu thuẫn với file này, file này thắng và file kia phải sửa lại** |
| 1 | `docs/architecture.md` | Kiến trúc hạ tầng tổng thể (VPC 3-Tier), các layer, nguyên tắc kiến trúc bắt buộc tuân thủ |
| 2 | `docs/system-flows.md` | Toàn bộ luồng hoạt động: auth, upload, xử lý AI bất đồng bộ, status callback, analytics, CI/CD, observability, DR |
| 3 | `docs/data-model.md` | Schema RDS PostgreSQL (tổng quan), DynamoDB, cấu trúc 5 S3 bucket |
| 4 | `docs/database-schema.md` | **Đặc tả chi tiết cột/kiểu/ràng buộc từng bảng RDS (6 bảng) + Prisma Schema mẫu + State Machine `matches.status` — dùng trực tiếp để code migration** |
| 5 | `docs/data-contracts.md` | **Schema chính xác 2 loại SQS message, DynamoDB item, JSON tracking trên S3, Parquet curated-data — bắt buộc AI Worker và Glue ETL tuân thủ tuyệt đối** |
| 6 | `docs/api-design.md` | 21 endpoint đầy đủ, request/response schema, auth flow RS256, quy tắc chống IDOR |
| 7 | `docs/backend-architecture.md` | **Cấu trúc module NestJS, cách xử lý Read Replica trong code, 2 guard chống IDOR, thứ tự interceptor, ví dụ code các service quan trọng** |
| 8 | `docs/iam-security-design.md` | Ma trận IAM cho 8 service/role, threat model, secrets management, checklist rà soát trước khi apply |
| 9 | `docs/terraform-structure.md` | Cấu trúc 8 module Terraform + stub analytics, thứ tự triển khai, quản lý state |
| 10 | `docs/naming-tagging-standard.md` | Chuẩn đặt tên và tag cho MỌI resource — bắt buộc tuân thủ tuyệt đối |
| 11 | `docs/cicd-design.md` | Pipeline CI/CD, branching strategy, rollback strategy |
| 12 | `docs/cost-estimate.md` | Ước tính chi phí, sàn cứng không giảm được, Budget $50/tháng, biện pháp tối ưu |
| 13 | `docs/roadmap.md` | **Roadmap triển khai chi tiết từng Phase, checklist task cụ thể (đã map với mã ADR) và định nghĩa hoàn thành (Deliverable)** |

Nếu còn file `.md` nào khác xuất hiện trong `docs/` ngoài danh sách trên, đọc luôn và coi là một phần của tài liệu thiết kế chính thức.

**Tài liệu bổ sung ngoài `docs/`:**
- `diagrams/MatchLens - Football Analytics Platform.drawio.png` — sơ đồ kiến trúc chính thức, đối chiếu trực quan với `docs/architecture.md`
- `knowledge/aws-glue.md` — sổ tay kiến thức chuyên đề về vận hành AWS Glue Serverless, cần đọc trước khi code `etl/player_stats_job.py`

**Quy tắc quan trọng:** Nếu phát hiện mâu thuẫn giữa yêu cầu mới của người dùng và tài liệu thiết kế đã chốt, PHẢI hỏi lại người dùng trước, không tự ý quyết định thay đổi kiến trúc. Nếu người dùng xác nhận muốn thay đổi, nhắc người dùng cập nhật lại đúng file thiết kế liên quan trong `docs/` trước khi code, để tài liệu và code không bị lệch nhau.

---

## 4. Tech Stack

| Layer | Công nghệ |
|---|---|
| Backend API | **NestJS (TypeScript) + Node 22 + pnpm + Prisma ~6.0** — chi tiết cấu trúc module tại `docs/backend-architecture.md` |
| Frontend | React (Vite) + TypeScript + pnpm |
| AI Inference | Python 3.12 + YOLOv11 (Ultralytics) + **ByteTrack/BoT-SORT** (sinh `track_id`) + **OpenCV** (homography), ONNX export nếu cần tối ưu |
| Database quan hệ | PostgreSQL (RDS) — Master + Standby (Multi-AZ ở staging/prod) + Read Replica (**chỉ staging/prod**) |
| NoSQL | DynamoDB (bảng `matchlens-{env}-match-events`) |
| Object Storage | S3 (**5 bucket**: raw-videos, processed-highlights, raw-tracking-data, curated-data, athena-results) |
| Serverless | Lambda × 3 (job-dispatcher, **status-updater** — duy nhất có RDS credential ngoài Backend, mediaconvert-trigger) |
| IaC | Terraform `~> 1.9` + AWS Provider `~> 5.60`, **8 module** theo `docs/terraform-structure.md` |
| CI/CD | GitHub Actions (OIDC, không dùng access key), Amazon ECR, Trivy — 2 pipeline build riêng cho Backend (Node.js) và Worker (Python) |
| Container Orchestration | ECS Fargate |
| Data & Analytics | AWS Glue, Amazon Athena, QuickSight (hoặc Streamlit) |
| Observability | CloudWatch, SNS, AWS Budget, EventBridge (auto-shutdown dev) |
| Security | IAM least-privilege, Secrets Manager (3 secret), CloudFront OAC + Signed URL, Security Hub, AWS Config, GuardDuty, ACM |
| Region | `ap-southeast-1` (Singapore) |

---

## 5. Cấu trúc thư mục dự án

```
MatchLens/
│
├── .github/
│   └── workflows/
│       ├── backend-cicd.yml        # Build, Lint (ESLint), Trivy scan & Deploy NestJS lên ECS
│       ├── worker-cicd.yml         # Build, Lint, Trivy scan & Deploy YOLOv11 Worker lên ECS
│       └── terraform-plan.yml      # Tự động chạy `terraform plan` khi tạo PR hạ tầng
│
├── diagrams/
│   └── MatchLens - Football Analytics Platform.drawio.png
│
├── docs/                            # Tài liệu Solution Architecture — xem danh sách đầy đủ ở mục 3
│   ├── decision-record.md           # ⭐ ADR — nguồn chân lý, đọc trước tiên
│   ├── architecture.md
│   ├── system-flows.md
│   ├── data-model.md
│   ├── database-schema.md
│   ├── data-contracts.md
│   ├── api-design.md
│   ├── backend-architecture.md
│   ├── iam-security-design.md
│   ├── terraform-structure.md
│   ├── naming-tagging-standard.md
│   ├── cicd-design.md
│   ├── cost-estimate.md
│   └── roadmap.md
│
├── knowledge/
│   └── aws-glue.md                  # Sổ tay kiến thức chuyên đề AWS Glue Serverless
│
├── infra/                           # Hạ tầng AWS dưới dạng code (Terraform ~1.9, AWS Provider ~5.60)
│   ├── modules/                     # 8 module + 1 stub
│   │   ├── network/                 # VPC 3-Tier (Public, Private App, Private DB), NAT Instance, IGW, VPC Gateway Endpoint
│   │   ├── compute/                 # ECS Fargate Cluster & Tasks, ALB, Auto Scaling
│   │   ├── database/                # RDS PostgreSQL (Master, Standby, Read Replica có điều kiện) & DynamoDB
│   │   ├── storage/                 # 5 S3 Buckets, CloudFront + OAC + Key Group, WAF
│   │   ├── messaging/               # 2 SQS Queue + 2 DLQ, 3 Lambda, S3 Event Notification
│   │   ├── security/                # 8 IAM Role least-privilege, ACM, Secrets Manager (2 secret), GitHub OIDC Provider, Security Hub, Config, GuardDuty
│   │   ├── observability/           # CloudWatch Dashboards, Alarms, SNS, AWS Budget, EventBridge auto-shutdown
│   │   ├── cicd/                    # ECR repository
│   │   └── analytics/               # STUB — chỉ có README, reserved cho Phase 6 (Glue/Athena/QuickSight)
│   ├── environments/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── global/
│       └── bootstrap/               # S3 Remote State + DynamoDB Lock (chạy 1 lần)
│
├── backend/                         # API Backend Service (NestJS + Node 22 + pnpm + Prisma 6)
│   ├── src/
│   │   ├── main.ts
│   │   ├── app.module.ts
│   │   ├── common/                  # 2 Guard chống IDOR (team-ownership, match-ownership), Interceptors, Filters
│   │   ├── config/                  # Validate biến môi trường bằng Joi
│   │   ├── prisma/                  # Prisma Module & Service (2 PrismaClient: write/read)
│   │   ├── aws/                     # S3 (Presigned URL), CloudFront (Signed URL), DynamoDB, Secrets Manager, Athena
│   │   ├── health/                  # GET /health cho ALB & ECS health check
│   │   ├── auth/                    # JWT RS256, Bcrypt, quản lý bảng refresh_tokens
│   │   ├── users/                   # CRUD Người dùng / HLV
│   │   ├── teams/                   # CRUD Đội bóng
│   │   ├── players/                 # CRUD Cầu thủ (module riêng)
│   │   └── matches/                 # Presigned URL, quản lý trận, status-transition.ts, track-mappings
│   ├── prisma/
│   │   ├── schema.prisma            # 6 model + enum MatchStatus, map từ docs/database-schema.md
│   │   └── migrations/
│   ├── test/
│   ├── Dockerfile                   # node:22-alpine, multi-stage
│   ├── package.json
│   └── pnpm-lock.yaml
│
├── worker/                          # AI Processing Service (Python 3.12 + YOLOv11)
│   ├── src/
│   │   ├── main.py                  # Polling SQS + check MARKER#COMPLETED (idempotency)
│   │   ├── detector.py              # YOLOv11 + ByteTrack/BoT-SORT sinh track_id
│   │   ├── homography.py            # 4 anchor point + cv2.findHomography → position_field
│   │   ├── s3_writer.py             # Batch 100-500 frames + schema_version + field_dimensions
│   │   ├── db_writer.py             # event_id TẤT ĐỊNH + MARKER#COMPLETED ở bước cuối
│   │   └── status_notifier.py       # Gửi callback vào SQS match-status-callbacks
│   ├── models/                      # File weights YOLOv11 (.pt hoặc .onnx)
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt / pyproject.toml
│
├── lambdas/                         # Lambda function source (Python)
│   ├── job_dispatcher/              # S3 Event → SQS video-processing-jobs + callback 'processing'
│   ├── status_updater/              # SQS callback → UPDATE matches.status (DUY NHẤT có RDS credential ngoài Backend)
│   │   └── transitions.py           # ⚠️ Phải khớp với backend/src/matches/status-transition.ts
│   └── mediaconvert_trigger/        # S3 Event prefix raw-clips/ → MediaConvert CreateJob
│
├── frontend/                        # Web App (React + Vite + TypeScript + pnpm)
│   ├── src/
│   │   ├── components/
│   │   ├── pages/                   # Upload video, Danh sách trận, Dashboard (heatmap Canvas)
│   │   └── services/                # Axios/API client gọi Backend qua ALB
│   ├── package.json
│   └── pnpm-lock.yaml
│
├── etl/                             # AWS Glue Serverless Data Pipeline
│   └── player_stats_job.py          # PySpark: JSON → Parquet Hive-partition, tính heatmap 10×6, quãng đường
│
├── CLAUDE.md                        # File này
├── README.md                        # Giới thiệu dự án cho CV & Portfolio
└── .gitignore
```

**Lưu ý:** cấu trúc `infra/` map trực tiếp với `docs/terraform-structure.md` — không tự ý đổi tên module hoặc thêm module ngoài danh sách đã thiết kế mà không cập nhật lại `docs/decision-record.md` và `docs/terraform-structure.md` trước.

**Thư mục `lambdas/` là mới** so với thiết kế ban đầu, phát sinh từ quyết định Q20 (status callback) và Q21 (MediaConvert trigger) — xem `docs/decision-record.md`.

---

## 6. Roadmap triển khai (theo Phase, không chia cứng theo tuần)

| Phase | Nội dung | Trạng thái |
|---|---|---|
| Design Phase | Toàn bộ tài liệu thiết kế trong `docs/` + sơ đồ kiến trúc trong `diagrams/` | ✅ Hoàn thành |
| **Decision Record** | **Chốt toàn bộ 34 câu hỏi mở + 5 quyết định hệ quả, đồng bộ 13 file `docs/` (2026-08-03)** | ✅ **Hoàn thành** |
| Phase 0 | Nền tảng ứng dụng cơ bản: schema RDS, API CRUD team/match/player, hạ tầng VPC 3-Tier/ALB/ECS/RDS cơ bản | ⏳ Sẵn sàng bắt đầu |
| Phase 1 | Highlight Engine: S3→SQS→Worker→YOLOv11→highlight clip, MediaConvert, CloudFront Signed URL | ⏳ Chưa bắt đầu |
| Phase 2 | Security & Governance: IAM least-privilege, Secrets Manager, Security Hub | ⏳ Chưa bắt đầu |
| Phase 3 | CI/CD: GitHub Actions 3 môi trường, Trivy scan, OIDC | ⏳ Chưa bắt đầu |
| Phase 4 | Observability: CloudWatch Dashboard, Alarm (gồm alarm cho status-callback DLQ), runbook | ⏳ Chưa bắt đầu |
| Phase 5 | Reliability & DR: RDS Multi-AZ, test restore, DR Plan | ⏳ Chưa bắt đầu |
| Phase 6 | Performance Analytics (mở rộng v2): Glue ETL, Athena, track_id mapping, heatmap | ⏳ Chưa bắt đầu, chỉ làm sau khi Phase 0-5 ổn định |
| Phase 7 | Cost Optimization (Budget $50, auto-shutdown dev) & hoàn thiện portfolio | ⏳ Chưa bắt đầu |

**Thứ tự thực hiện Terraform module khi bắt đầu code hạ tầng** (chi tiết ở `docs/terraform-structure.md` mục 7):
1. `infra/global/bootstrap/` (S3 backend + DynamoDB lock)
2. `infra/modules/network/` (VPC 3-Tier + VPC Gateway Endpoint)
3. `infra/modules/storage/` (5 bucket)
4. `infra/modules/database/`
5. `infra/modules/security/` ⚠️ **đứng TRƯỚC messaging** — vì `messaging` cần role ARN để gắn vào 3 Lambda
6. `infra/modules/messaging/`
7. `infra/modules/compute/`
8. `infra/modules/observability/`
9. `infra/modules/cicd/` + CI/CD workflow (`.github/workflows/`)

Thứ tự này đã thay đổi so với bản thiết kế đầu (`security` trước `messaging`) để phá vỡ circular dependency phát sinh từ quyết định Q20 — xem `docs/decision-record.md`.

---

## 7. Quy tắc bắt buộc khi Claude Code triển khai

### 7.1. Về hạ tầng (Terraform)
- Mọi resource PHẢI đặt tên và gắn tag theo đúng `docs/naming-tagging-standard.md`, không tự sáng tạo pattern khác
- Mọi IAM Role PHẢI theo đúng ma trận quyền trong `docs/iam-security-design.md` — không cấp quyền rộng hơn để "cho tiện", kể cả trong lúc test. Dùng checklist ở mục 8 của file đó trước khi apply
- Không hardcode credential trong code hoặc Terraform — dùng Secrets Manager, đọc qua biến môi trường tại runtime
- Pin version: `required_version = "~> 1.9"`, `hashicorp/aws = "~> 5.60"` trong `versions.tf` của MỌI module
- Environment `dev` dùng cấu hình tiết kiệm: **RDS Single-AZ, KHÔNG Read Replica vật lý, 1 NAT Instance** — theo `docs/cost-estimate.md`, không tự ý bật Multi-AZ/cấu hình đắt ở dev
- **VPC Gateway Endpoint cho S3/DynamoDB là bắt buộc ngay Phase 0** (miễn phí, tránh phí NAT cho traffic video)

### 7.2. Về API/Backend
- Endpoint PHẢI theo đúng danh sách và schema trong `docs/api-design.md`
- Mọi endpoint (trừ `/auth/*` và `/health`) PHẢI qua guard kiểm tra quyền sở hữu resource (chống IDOR). **Có 2 guard riêng**: `TeamOwnershipGuard` (route có `:team_id`) và `MatchOwnershipGuard` (route chỉ có `:match_id`) — xem `docs/backend-architecture.md` mục 7
- **Cả 2 guard PHẢI query qua `prisma.write` (Master)**, không dùng Replica — tránh 403 oan do replication lag
- Upload video PHẢI qua presigned URL, Backend không xử lý file trực tiếp
- Thao tác ghi luôn dùng `prisma.write`, đọc tải cao dùng `prisma.read` — theo `docs/backend-architecture.md` mục 4.3
- API DTO dùng **snake_case**, code TypeScript dùng **camelCase**, map qua `@Expose({ name })`
- Backend chỉ được ghi 2 transition của `matches.status`: `→ pending` và `pending → uploaded`. Ba transition còn lại do Lambda `status-updater-fn`
- `GET /highlights` PHẢI filter bỏ item DynamoDB có `event_id` bắt đầu bằng `MARKER#`

### 7.3. Về AI Worker
- Worker chỉ nhận job qua SQS, không expose endpoint public
- **Idempotent bắt buộc**: kiểm tra `MARKER#COMPLETED` trong DynamoDB trước khi xử lý; ghi marker ở **bước cuối cùng** sau khi mọi dữ liệu đã ghi xong
- **`event_id` PHẢI tất định** (`{ts_ms:013d}-{hash10}`), không dùng ULID random — nếu không, retry sẽ tạo highlight trùng
- Dữ liệu ghi ra DynamoDB/S3 PHẢI tuân thủ đúng 100% schema trong `docs/data-contracts.md`, validate bằng `pydantic` trước khi ghi
- Worker **KHÔNG** kết nối RDS, **KHÔNG** gọi MediaConvert. Cập nhật status qua SQS `match-status-callbacks`; transcode do Lambda riêng kích hoạt
- Worker chỉ ghi clip vào prefix `raw-clips/`, tuyệt đối không ghi vào `clips/`

### 7.4. Về quy trình làm việc
- **Đọc `docs/decision-record.md` trước tiên** ở mỗi phiên làm việc — đây là nguồn chân lý cho mọi quyết định đã chốt
- Trước khi tạo code cho 1 phần hạ tầng/tính năng mới, đọc lại đúng file thiết kế tương ứng trong `docs/`
- Nếu cần quyết định gì chưa có trong tài liệu, hỏi người dùng trước khi tự quyết định và code. Sau khi chốt, ghi vào `docs/decision-record.md` **trước**, rồi mới sửa file `docs/` liên quan, rồi mới code
- Khi sửa `status-transition` logic, PHẢI sửa **cả 2 nơi**: `backend/src/matches/status-transition.ts` và `lambdas/status_updater/transitions.py`
- Sau khi hoàn thành 1 Phase, cập nhật trạng thái ở bảng Roadmap (mục 6) VÀ tick checklist trong `docs/roadmap.md`
- Luôn tuân thủ quy tắc quyền hạn thao tác ở mục 2 — đề xuất và hướng dẫn, không tự động thực thi trừ khi được cho phép rõ ràng

---

## 8. Thông tin người thực hiện dự án

- Sinh viên năm cuối ngành CNTT, có kinh nghiệm Fullstack (backend-leaning) và vừa hoàn thành thực tập Infrastructure Engineer (AWS ECS + Terraform)
- Đã có kinh nghiệm với YOLOv11 từ đồ án tốt nghiệp (Driver Monitoring System) — tái sử dụng kiến thức này cho AI Worker Service
- Mục tiêu: hoàn thiện dự án làm portfolio ứng tuyển Backend Developer / DevOps / Infrastructure Engineer trong đợt tuyển dụng tháng 8/2026

---

## 9. Ghi chú khác

- Toàn bộ giao tiếp/tài liệu trong dự án ưu tiên tiếng Việt (trừ code, tên biến, tên resource — giữ tiếng Anh theo chuẩn kỹ thuật)
- Khi commit message, dùng tiếng Anh ngắn gọn theo chuẩn Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`...) để giữ thói quen chuẩn doanh nghiệp — nhưng Claude Code chỉ soạn sẵn message, không tự `git commit`/`git push` (xem mục 2)
