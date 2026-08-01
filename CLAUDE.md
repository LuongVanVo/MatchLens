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
| 1 | `docs/architecture.md` | Kiến trúc hạ tầng tổng thể, các layer, nguyên tắc kiến trúc bắt buộc tuân thủ |
| 2 | `docs/system-flows.md` | Toàn bộ luồng hoạt động: auth, upload, xử lý AI bất đồng bộ, analytics, CI/CD, observability, DR |
| 3 | `docs/data-model.md` | Schema RDS PostgreSQL (tổng quan), DynamoDB, cấu trúc S3 bucket |
| 4 | `docs/database-schema.md` | **Đặc tả chi tiết cột/kiểu dữ liệu/ràng buộc từng bảng RDS + Prisma Schema mẫu — dùng trực tiếp để code migration** |
| 5 | `docs/data-contracts.md` | **Schema chính xác SQS message, DynamoDB MatchEvents, JSON tracking data trên S3, Parquet curated-data — bắt buộc AI Worker và Glue ETL tuân thủ tuyệt đối** |
| 6 | `docs/api-design.md` | Danh sách endpoint đầy đủ, request/response schema, auth flow |
| 7 | `docs/backend-architecture.md` | **Cấu trúc module NestJS, cách xử lý Read Replica trong code, ví dụ code các service quan trọng** |
| 8 | `docs/iam-security-design.md` | Ma trận IAM Role cho từng service, threat model, secrets management |
| 9 | `docs/terraform-structure.md` | Cấu trúc module Terraform, thứ tự triển khai, quản lý state |
| 10 | `docs/naming-tagging-standard.md` | Chuẩn đặt tên và tag cho MỌI resource — bắt buộc tuân thủ tuyệt đối |
| 11 | `docs/cicd-design.md` | Pipeline CI/CD, branching strategy, rollback strategy |
| 12 | `docs/cost-estimate.md` | Ước tính chi phí, các biện pháp tối ưu cần áp dụng khi code hạ tầng |
| 13 | `docs/roadmap.md` | **Roadmap triển khai chi tiết từng Phase, checklist task cụ thể và định nghĩa hoàn thành (Deliverable)** |

Nếu còn file `.md` nào khác xuất hiện trong `docs/` ngoài danh sách trên, đọc luôn và coi là một phần của tài liệu thiết kế chính thức.

**Tài liệu bổ sung ngoài `docs/`:**
- `diagrams/MatchLens - Football Analytics Platform.drawio.png` — sơ đồ kiến trúc chính thức, đối chiếu trực quan với `docs/architecture.md`
- `knowledge/aws-glue.md` — sổ tay kiến thức chuyên đề về vận hành AWS Glue Serverless, cần đọc trước khi code `etl/player_stats_job.py`

**Quy tắc quan trọng:** Nếu phát hiện mâu thuẫn giữa yêu cầu mới của người dùng và tài liệu thiết kế đã chốt, PHẢI hỏi lại người dùng trước, không tự ý quyết định thay đổi kiến trúc. Nếu người dùng xác nhận muốn thay đổi, nhắc người dùng cập nhật lại đúng file thiết kế liên quan trong `docs/` trước khi code, để tài liệu và code không bị lệch nhau.

---

## 4. Tech Stack

| Layer | Công nghệ |
|---|---|
| Backend API | **NestJS (TypeScript) + pnpm + Prisma ORM** — chi tiết cấu trúc module tại `docs/backend-architecture.md` |
| Frontend | React (Vite) + TypeScript + pnpm |
| AI Inference | Python 3.12 + YOLOv11 (Ultralytics), ONNX export nếu cần tối ưu tốc độ |
| Database quan hệ | PostgreSQL (RDS) — Master + Standby (Multi-AZ) + Read Replica |
| NoSQL | DynamoDB (bảng `MatchEvents`) |
| Object Storage | S3 (4 bucket: raw-videos, processed-highlights, raw-tracking-data, curated-data) |
| IaC | Terraform, module hóa theo `docs/terraform-structure.md` |
| CI/CD | GitHub Actions, Amazon ECR, Trivy (image scan) — 2 pipeline build riêng cho Backend (Node.js) và Worker (Python) |
| Container Orchestration | ECS Fargate |
| Data & Analytics | AWS Glue, Amazon Athena, QuickSight |
| Observability | CloudWatch, SNS |
| Security | IAM least-privilege, Secrets Manager, Security Hub, AWS Config, GuardDuty, ACM |

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
│   └── cost-estimate.md
│
├── knowledge/
│   └── aws-glue.md                  # Sổ tay kiến thức chuyên đề AWS Glue Serverless
│
├── infra/                           # Hạ tầng AWS dưới dạng code (Terraform)
│   ├── modules/
│   │   ├── network/                 # VPC 3-Tier (Public, Private App, Private DB), NAT, IGW
│   │   ├── compute/                 # ECS Fargate Cluster & Tasks, ALB, Auto Scaling
│   │   ├── database/                # RDS PostgreSQL (Master, Standby, Read Replica) & DynamoDB
│   │   ├── storage/                 # 4 S3 Buckets (Raw, Highlight, Tracking, Curated), CloudFront, WAF
│   │   ├── messaging/                # SQS Queue, DLQ, Lambda Dispatcher
│   │   ├── security/                 # IAM Roles least-privilege, ACM SSL/TLS, Secrets Manager
│   │   └── observability/            # CloudWatch Dashboards, Alarms, SNS topic
│   ├── environments/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── global/
│       └── bootstrap/               # Khởi tạo S3 Remote State & DynamoDB Lock
│
├── backend/                         # API Backend Service (NestJS + TypeScript + pnpm)
│   ├── src/
│   │   ├── main.ts
│   │   ├── app.module.ts
│   │   ├── common/                  # Guards, Interceptors, Filters (chống IDOR, JWT auth)
│   │   ├── config/                  # Validate biến môi trường bằng Joi
│   │   ├── prisma/                  # Prisma Module & Service (quản lý kết nối Master & Read Replica)
│   │   ├── aws/                     # Tích hợp S3 (Presigned URL), DynamoDB (MatchEvents)
│   │   ├── auth/                    # Xử lý JWT Authentication & Bcrypt password
│   │   ├── users/                   # CRUD Người dùng / HLV
│   │   ├── teams/                   # CRUD Đội bóng & Cầu thủ
│   │   └── matches/                 # Cấp Presigned URL upload video & Quản lý trận đấu
│   ├── prisma/
│   │   ├── schema.prisma            # Code mapping DB từ docs/database-schema.md
│   │   └── migrations/
│   ├── test/
│   ├── Dockerfile
│   ├── package.json
│   └── pnpm-lock.yaml
│
├── worker/                          # AI Processing Service (Python 3.12 + YOLOv11)
│   ├── src/
│   │   ├── main.py                  # Tiến trình chính: Polling SQS Queue
│   │   ├── detector.py              # Logic nhận diện YOLOv11 (cầu thủ, bóng, sự kiện)
│   │   ├── media.py                 # Gọi API MediaConvert transcode highlight
│   │   ├── s3_writer.py             # Đóng gói batch 100-500 frames đẩy lên S3 tracking
│   │   └── db_writer.py             # Ghi timestamp ULID sự kiện vào DynamoDB
│   ├── models/                      # File weights YOLOv11 (.pt hoặc .onnx)
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt / pyproject.toml
│
├── frontend/                        # Web App (React + Vite + TypeScript + pnpm)
│   ├── src/
│   │   ├── components/
│   │   ├── pages/                   # Upload video, Danh sách trận, Dashboard thống kê
│   │   └── services/                # Axios/API client gọi Backend qua ALB
│   ├── package.json
│   └── pnpm-lock.yaml
│
├── etl/                              # AWS Glue Serverless Data Pipeline
│   └── player_stats_job.py           # PySpark/Python: JSON -> Parquet & tính heatmap, quãng đường
│
├── CLAUDE.md                         # File này
├── README.md                         # Giới thiệu dự án cho CV & Portfolio
└── .gitignore
```

**Lưu ý:** Cấu trúc `infra/` map trực tiếp với `docs/terraform-structure.md` — không tự ý đổi tên module hoặc thêm module ngoài danh sách đã thiết kế mà không cập nhật lại tài liệu thiết kế tương ứng trước.

---

## 6. Roadmap triển khai (theo Phase, không chia cứng theo tuần)

| Phase | Nội dung | Trạng thái |
|---|---|---|
| Design Phase | Toàn bộ 12 tài liệu thiết kế trong `docs/` + sơ đồ kiến trúc trong `diagrams/` | ✅ Hoàn thành |
| Phase 0 | Nền tảng ứng dụng cơ bản: schema RDS, API CRUD team/match/player, hạ tầng VPC/ALB/ECS/RDS cơ bản | ⏳ Chưa bắt đầu |
| Phase 1 | Highlight Engine: S3→SQS→Worker→YOLOv11→highlight clip, MediaConvert, CloudFront | ⏳ Chưa bắt đầu |
| Phase 2 | Security & Governance: IAM least-privilege, Secrets Manager, Security Hub | ⏳ Chưa bắt đầu |
| Phase 3 | CI/CD: GitHub Actions 3 môi trường, Trivy scan | ⏳ Chưa bắt đầu |
| Phase 4 | Observability: CloudWatch Dashboard, Alarm, runbook | ⏳ Chưa bắt đầu |
| Phase 5 | Reliability & DR: RDS Multi-AZ, test restore, DR Plan | ⏳ Chưa bắt đầu |
| Phase 6 | Performance Analytics (mở rộng v2): Glue ETL, Athena, QuickSight | ⏳ Chưa bắt đầu, chỉ làm sau khi Phase 0-5 ổn định |
| Phase 7 | Cost Optimization & hoàn thiện portfolio | ⏳ Chưa bắt đầu |

**Thứ tự thực hiện Terraform module khi bắt đầu code hạ tầng** (chi tiết ở `docs/terraform-structure.md` mục 7):
1. `infra/global/bootstrap/` (S3 backend + DynamoDB lock)
2. `infra/modules/network/`
3. `infra/modules/storage/`
4. `infra/modules/database/`
5. `infra/modules/messaging/`
6. `infra/modules/security/`
7. `infra/modules/compute/`
8. `infra/modules/observability/`
9. CI/CD workflow (`.github/workflows/`)

---

## 7. Quy tắc bắt buộc khi Claude Code triển khai

### 7.1. Về hạ tầng (Terraform)
- Mọi resource PHẢI đặt tên và gắn tag theo đúng `docs/naming-tagging-standard.md`, không tự sáng tạo pattern khác
- Mọi IAM Role PHẢI theo đúng ma trận quyền trong `docs/iam-security-design.md` — không cấp quyền rộng hơn để "cho tiện", kể cả trong lúc test
- Không hardcode credential trong code hoặc Terraform — dùng Secrets Manager, đọc qua biến môi trường tại runtime
- Environment `dev` dùng cấu hình tiết kiệm chi phí (RDS Single-AZ, NAT Instance, 1 NAT Instance dùng chung cả 2 AZ) theo `docs/cost-estimate.md`, không tự ý bật Multi-AZ/cấu hình đắt ở dev

### 7.2. Về API/Backend
- Endpoint PHẢI theo đúng danh sách và schema trong `docs/api-design.md`
- Mọi endpoint (trừ `/auth/*`) PHẢI qua middleware/guard kiểm tra quyền sở hữu resource (chống IDOR) — xem `docs/api-design.md` mục 8 và `docs/backend-architecture.md` mục 7
- Upload video PHẢI qua presigned URL, Backend không xử lý file trực tiếp
- Thao tác ghi luôn dùng Prisma Client trỏ Master, thao tác đọc tải cao dùng Prisma Client trỏ Read Replica — theo đúng quy tắc ở `docs/backend-architecture.md` mục 4

### 7.3. Về AI Worker
- Worker chỉ nhận job qua SQS, không expose endpoint public
- Phải thiết kế idempotent (kiểm tra job đã xử lý chưa trước khi ghi đè) để tránh xử lý trùng khi SQS redeliver message
- Dữ liệu ghi ra DynamoDB/S3 PHẢI tuân thủ đúng 100% schema trong `docs/data-contracts.md`, không tự ý đổi cấu trúc field

### 7.4. Về quy trình làm việc
- Trước khi tạo code cho 1 phần hạ tầng/tính năng mới, đọc lại đúng file thiết kế tương ứng trong `docs/`
- Nếu cần quyết định gì chưa có trong tài liệu thiết kế (xem các mục "Câu hỏi còn mở" ở cuối mỗi file thiết kế), hỏi người dùng trước khi tự quyết định và code
- Sau khi hoàn thành 1 Phase, cập nhật trạng thái trong bảng Roadmap (mục 6 của file này)
- Luôn tuân thủ quy tắc quyền hạn thao tác đã nêu ở mục 2 — đề xuất và hướng dẫn, không tự động thực thi trừ khi được cho phép rõ ràng

---

## 8. Thông tin người thực hiện dự án

- Sinh viên năm cuối ngành CNTT, có kinh nghiệm Fullstack (backend-leaning) và vừa hoàn thành thực tập Infrastructure Engineer (AWS ECS + Terraform)
- Đã có kinh nghiệm với YOLOv11 từ đồ án tốt nghiệp (Driver Monitoring System) — tái sử dụng kiến thức này cho AI Worker Service
- Mục tiêu: hoàn thiện dự án làm portfolio ứng tuyển Backend Developer / DevOps / Infrastructure Engineer trong đợt tuyển dụng tháng 8/2026

---

## 9. Ghi chú khác

- Toàn bộ giao tiếp/tài liệu trong dự án ưu tiên tiếng Việt (trừ code, tên biến, tên resource — giữ tiếng Anh theo chuẩn kỹ thuật)
- Khi commit message, dùng tiếng Anh ngắn gọn theo chuẩn Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`...) để giữ thói quen chuẩn doanh nghiệp — nhưng Claude Code chỉ soạn sẵn message, không tự `git commit`/`git push` (xem mục 2)
