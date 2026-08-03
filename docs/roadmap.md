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
- [ ] `infra/global/bootstrap/`: S3 backend `matchlens-terraform-state-{account_id}` + DynamoDB lock `matchlens-terraform-locks`, region `ap-southeast-1` (Q7, Q8)
- [ ] `infra/modules/network/`: VPC **3-Tier** 2AZ (Public, Private App, Private DB — Private DB **không có route internet**), **1 NAT Instance** ở AZ-A cho dev, Internet Gateway, **VPC Gateway Endpoint cho S3 + DynamoDB** (Q1, Q2, Q29)
- [ ] `infra/modules/storage/`: **5 S3 bucket** (raw-videos, processed-highlights, raw-tracking-data, curated-data, **athena-results**), lifecycle policy (Q30)
- [ ] `infra/modules/database/`: RDS PostgreSQL Master `matchlens-{env}-postgres` (Single-AZ ở dev), **KHÔNG tạo Read Replica ở dev** (`create_read_replica = false`), DynamoDB `matchlens-{env}-match-events` (Q3, Q4)
- [ ] `infra/modules/security/`: IAM role cho Backend + secret `db-credentials`, `jwt-keypair` (RS256) — phần role cho Worker/Lambda để Phase 1-2
- [ ] `infra/modules/compute/`: ECS Cluster, ALB, Target Group + health check `/health`, Task Definition + Service cho Backend API (chưa cần Worker)
- [ ] `infra/modules/analytics/README.md`: stub ghi chú "Reserved for Phase 6" (Q6)
- [ ] `backend/`: khởi tạo NestJS + pnpm, **Node 22**, **Prisma ~6.0** với 2 PrismaClient (`datasourceUrl` syntax), Pino logging (Q15, Q33)
- [ ] Prisma schema + migration đầu tiên: 6 model (`User`, `RefreshToken`, `Team`, `Player`, `Match`, `MatchTrackMapping`) + enum `MatchStatus` + raw SQL migration cho CHECK constraint (Q12, D1)
- [ ] Code CRUD: `auth` (register/login/refresh/**logout** với bảng `refresh_tokens`), `teams`, `players` (module riêng), `matches` (chưa cần `upload-url`/`highlights`/`stats`) (Q12, Q17)
- [ ] **2 guard chống IDOR**: `TeamOwnershipGuard` + `MatchOwnershipGuard`, cả 2 query qua `prisma.write` (Q11)
- [ ] `status-transition.ts`: validate state machine 5 trạng thái, Backend chỉ ghi `pending`/`uploaded` (Q10, Q20)
- [ ] `HealthModule` (`GET /health`) trả `{status, db, timestamp}`, không auth, không wrapper (Q16)
- [ ] Serialization: `ClassSerializerInterceptor` + `@Expose({name})` map camelCase → snake_case, chạy **trước** `ResponseTransformInterceptor` (Q13, D5)
- [ ] `frontend/`: khởi tạo React + Vite, trang đăng nhập, tạo team, danh sách trận đấu

### Deliverable — Phase 0 coi là xong khi
- Đăng ký/đăng nhập/logout, tạo team, thêm player, tạo match qua giao diện web thật, chạy trên AWS (không phải chỉ local)
- ALB Health Check pass (`/health` trả 200), ECS Service ổn định
- Thử truy cập team/match của user khác → nhận `403`, chứng minh guard chống IDOR hoạt động

### Phụ thuộc
- Không phụ thuộc Phase nào khác — làm đầu tiên

### Thứ tự apply Terraform (lưu ý thay đổi)
`bootstrap` → `network` → `storage` → `database` → **`security`** → `compute`

`security` đứng **trước** `messaging` (Phase 1) vì `messaging` cần role ARN để gắn vào Lambda. Xem `terraform-structure.md` mục 7.

---

## Phase 1 — Highlight Engine

**Mục tiêu:** Tính năng lõi hoạt động — upload video, AI xử lý, trả về highlight tự động.

### Task cụ thể
- [ ] `infra/modules/storage/`: CloudFront (**1 distribution, 2 origin**) + **OAC** + **key group cho Signed URL**, WAF, lifecycle xóa prefix `raw-clips/` sau 7 ngày (Q23)
- [ ] `infra/modules/messaging/`: **2 SQS queue + 2 DLQ** (`video-processing-jobs`, `match-status-callbacks`), **3 Lambda** (job-dispatcher, **status-updater** trong VPC, **mediaconvert-trigger**), S3 Event Notification với `filter_prefix = "raw-clips/"` (Q19b, Q20, Q21, Q28)
- [ ] `infra/modules/security/`: bổ sung role cho Worker, 3 Lambda role mới, MediaConvert service role, secret `cloudfront-signing-key` (Q20, Q21, Q23)
- [ ] `infra/modules/compute/`: bổ sung ECS Service cho AI Worker, autoscale theo queue depth (về 0 khi rỗng)
- [ ] `backend/`: endpoint `upload-url` (validate content-type + 2GB + rate-limit 10/phút), `confirm-upload`, `status`, `highlights` (**filter bỏ item `MARKER#`**, sinh CloudFront Signed URL 4h) (Q23, Q27, Q28, D5)
- [ ] `worker/`: `main.py` (poll SQS + **check `MARKER#COMPLETED` trước khi xử lý**), `detector.py` (YOLOv11 + **ByteTrack/BoT-SORT** sinh `track_id`), `homography.py` (**4 anchor point + cv2.findHomography** tính `position_field`), `s3_writer.py` (batch JSON + `schema_version` + `field_dimensions`), `db_writer.py` (**`event_id` tất định** + marker ở bước cuối), `status_notifier.py` (gửi callback SQS) (Q20, Q22, Q24, Q25, Q26)
- [ ] `lambdas/status_updater/`: đọc callback queue, `transitions.py` validate state machine (**phải khớp** với `backend/src/matches/status-transition.ts`), UPDATE RDS (Q20)
- [ ] `lambdas/mediaconvert_trigger/`: nhận S3 Event prefix `raw-clips/`, tạo MediaConvert job ghi output sang `clips/` (Q21)
- [ ] `frontend/`: trang upload video (presigned URL), xem highlight (video player + CloudFront Signed URL), polling trạng thái

### Deliverable — Phase 1 coi là xong khi
- Upload video thật qua giao diện, hệ thống tự động xử lý, xem được ít nhất 1 highlight clip
- DLQ hoạt động đúng khi cố tình cho job lỗi (test 1 lần)
- **Test idempotency:** cho SQS redeliver 1 message đã xử lý xong → Worker bỏ qua, DynamoDB **không** phát sinh item trùng
- **Test chống vòng lặp:** MediaConvert ghi output xong → xác nhận Lambda `mediaconvert-trigger` **không** tự kích hoạt lại
- **Test callback:** cố tình cho `status-updater-fn` fail → message vào DLQ → Alarm bắn (không để status treo âm thầm)

### Phụ thuộc
- Cần Phase 0 xong (đặc biệt: Backend, RDS, VPC, storage đã có)

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
- [ ] `infra/modules/observability/`: CloudWatch Dashboard, SNS Topic, và Alarm cho:
  - **DLQ `video-processing-dlq`** có message
  - **DLQ `match-status-callbacks-dlq`** có message — quan trọng đặc biệt: nếu `status-updater-fn` chết thì status treo `processing` vĩnh viễn, user không biết (D2)
  - ECS service health check fail (Backend + Worker)
  - RDS storage vượt ngưỡng, RDS CPU cao
  - ALB 5xx rate vượt ngưỡng
  - Lambda error rate cho cả 3 Lambda
- [ ] Kết nối SNS với email/Slack
- [ ] Viết 2-3 runbook xử lý sự cố (`knowledge/runbooks.md`), khuyến nghị bao gồm: "match treo ở trạng thái processing", "DLQ có message", "RDS failover"

### Deliverable — Phase 4 coi là xong khi
- Alarm thực sự bắn thông báo (test bằng cách cố tình gây lỗi), có ít nhất 2 runbook cụ thể
- Test riêng kịch bản `status-updater-fn` fail → xác nhận Alarm bắn, không để silent failure

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
- [ ] `etl/player_stats_job.py`: đọc `knowledge/aws-glue.md` trước khi code. Xử lý theo `docs/data-contracts.md` mục 3-4: kiểm tra `schema_version`, quy đổi tọa độ bằng `field_dimensions` **đọc từ file** (không hardcode 105/68), nhóm theo **`track_id`**, chia lưới heatmap **10×6**, ghi Parquet **Hive-partition** `team_id=.../match_id=...` (Q19, Q24, Q25, Q26, Q32)
- [ ] Cấu hình Glue Crawler + Glue Data Catalog `matchlens_{env}` (nhận `team_id`/`match_id` thành partition column)
- [ ] Cấu hình Athena Workgroup `matchlens-{env}-workgroup`, output tới bucket `athena-results` (Q30)
- [ ] `infra/modules/analytics/`: chuyển stub thành module thật (Glue Job, Crawler, Athena Workgroup)
- [ ] `backend/`: endpoint `GET /matches/{id}/stats` — **cache kết quả**, không query Athena trực tiếp trong luồng request. JOIN `match_track_mappings` để trả tên cầu thủ thật. Trả **mảng số heatmap**, không phải PNG (Q31)
- [ ] `backend/`: endpoint `PUT /matches/{id}/track-mappings` + `track-mappings.service.ts` (Q25, D1)
- [ ] `frontend/`: trang thống kê — hiển thị "Player Track #N (Home)" + dropdown gán cầu thủ; render heatmap bằng **HTML5 Canvas** đè lên hình sân (Q31)
- [ ] Dashboard: QuickSight **hoặc** Streamlit tự build — xem lại quyết định chi phí ở `cost-estimate.md` mục 4

### Deliverable — Phase 6 coi là xong khi
- Xem được heatmap + chỉ số (quãng đường, tốc độ) của ít nhất 1 `track_id` từ 1 trận đã xử lý
- HLV gán được `Track #1 → Quang Hải`, dashboard hiển thị tên thật thay vì số track
- Athena query dùng partition (kiểm tra `Data scanned` trong query result — phải nhỏ, không scan toàn bucket)

### Phụ thuộc
- Cần Phase 0-1 xong (cần dữ liệu tracking thô đã có trong S3 raw-tracking-data)
- Chỉ bắt đầu sau khi Phase 0-5 đã chạy ổn định

---

## Phase 7 — Cost Optimization & Hoàn thiện Portfolio

**Mục tiêu:** Tối ưu chi phí, hoàn thiện tài liệu để sẵn sàng đưa vào CV.

### Task cụ thể
- [ ] Rà soát tag đầy đủ cho mọi resource theo `docs/naming-tagging-standard.md` (đặc biệt `DataClassification = confidential` cho RDS + 3 secret)
- [ ] Thiết lập **AWS Budget $50/tháng**, alert 50% / 80% / 100%, filter theo tag `Project=MatchLens` (Q33)
- [ ] **EventBridge auto-shutdown dev** — 2 rule (Q33, D4):
  - `0 17 * * ? *` UTC (00:00 VN): ECS desired count → 0, `StopDBInstance`
  - `0 1 * * ? *` UTC (08:00 VN): `StartDBInstance`, ECS desired count → 1
  - Lưu ý: RDS **không có "pause"** (đó là Aurora Serverless), chỉ có stop; AWS tự start lại sau tối đa 7 ngày
- [ ] ECR Lifecycle Policy giữ tối đa 10 image gần nhất (image Worker ~2GB do PyTorch)
- [ ] Áp dụng lifecycle S3 còn lại: xóa `raw-clips/` sau 7 ngày, `athena-results` sau 7 ngày, Glacier cho `raw-videos`
- [ ] Cập nhật `README.md` hoàn chỉnh: giới thiệu, kiến trúc, hướng dẫn chạy, ảnh/video demo, và **ghi rõ 2 giới hạn đã biết**: (a) giả định camera tĩnh cho homography (Q24), (b) chưa quét virus video upload
- [ ] Viết case study ngắn (vấn đề — giải pháp — số liệu đo được)

### Deliverable — Phase 7 coi là xong khi
- Chi phí thực tế theo dõi được qua Budget, auto-shutdown hoạt động (xác nhận sáng hôm sau ECS/RDS tự lên lại)
- README đầy đủ, có ít nhất 1 video demo ngắn (2-3 phút)

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
