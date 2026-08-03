# MatchLens — Architectural Decision Record (ADR)

> Nguồn chân lý chính thức cho toàn bộ quyết định kiến trúc đã chốt sau vòng audit thiết kế (2026-08-03). Mọi file khác trong `docs/` đã được cập nhật theo file này. Khi có xung đột giữa file khác và file này, **file này thắng** — và file kia phải được sửa lại cho khớp.
>
> Phạm vi: 34 câu hỏi phát sinh từ audit (Q1–Q34) + 5 quyết định hệ quả phát sinh trong lúc áp dụng (D1–D5).

---

## Cách đọc file này

| Cột | Ý nghĩa |
|---|---|
| **Mã** | Mã tham chiếu, dùng khi commit/PR (`refs Q20`) |
| **Quyết định** | Nội dung đã chốt, không diễn giải lại |
| **File bị ảnh hưởng** | Nơi quyết định này đã được ghi vào |

---

## GROUP A — Phase 0 Blockers (Core Infra & Backend)

### Q1 — VPC 3-Tier (thay vì 2-tier)

Kiến trúc VPC **bắt buộc 3 tier**, trải 2 AZ:

| Tier | Nội dung | Route ra internet |
|---|---|---|
| **Public Subnet** | ALB, NAT Instance | Qua Internet Gateway |
| **Private App Subnet** | ECS Fargate (Backend API, AI Worker), `status-updater-lambda` | Qua NAT Instance (outbound only) |
| **Private DB Subnet** | RDS PostgreSQL (Master, Standby, Read Replica) | **Zero internet routing** — route table không có route `0.0.0.0/0` |

RDS bị cô lập hoàn toàn: không có đường ra internet, chỉ nhận inbound port 5432 từ Security Group của ECS và của `status-updater-lambda`.

**File ảnh hưởng:** `architecture.md` mục 2, `terraform-structure.md` mục 3.1

---

### Q2 — Số NAT Instance theo environment

| Environment | NAT Instance | Ghi chú |
|---|---|---|
| `dev` | **1** instance, đặt ở Public Subnet AZ-A | Private subnet AZ-B route cross-AZ về NAT ở AZ-A. Chấp nhận single point of failure để tiết kiệm, có phát sinh phí cross-AZ data transfer (không đáng kể ở dev) |
| `staging` / `prod` | **2** instance, 1 per AZ | HA thật, mỗi AZ có route table riêng trỏ về NAT cùng AZ |

Terraform: điều khiển qua biến `nat_instance_count` (dev = 1, staging/prod = 2).

**File ảnh hưởng:** `architecture.md` mục 2, `cost-estimate.md` mục 2.7, `terraform-structure.md` mục 3.1

---

### Q3 — Read Replica không deploy ở dev

| Environment | Read Replica vật lý | `DATABASE_URL_MASTER` | `DATABASE_URL_REPLICA` |
|---|---|---|---|
| `dev` | **Không tạo** | endpoint Master | **cùng endpoint Master** |
| `staging` / `prod` | Tạo | endpoint Master | endpoint Replica |

Điều khiển qua biến Terraform `create_read_replica` (bool). Code Backend **không thay đổi** giữa các môi trường — vẫn luôn có 2 PrismaClient (`write`/`read`), chỉ khác giá trị biến môi trường. Nhờ vậy logic chọn client được viết đúng ngay từ dev, không phải sửa khi lên prod.

**File ảnh hưởng:** `data-model.md` mục 1.1.1, `backend-architecture.md` mục 4.4, `cost-estimate.md` mục 2.2

---

### Q4 — RDS identifier

| Instance | Identifier |
|---|---|
| Master | `matchlens-{env}-postgres` |
| Read Replica | `matchlens-{env}-postgres-replica` |
| Standby (Multi-AZ) | Không có identifier riêng — AWS quản lý ngầm |

**File ảnh hưởng:** `naming-tagging-standard.md` mục 2.2

---

### Q5 — Giữ 8 Terraform module

Danh sách chính thức: `network`, `compute`, `database`, `storage`, `messaging`, `security`, `observability`, `cicd`. Module `cicd/` chịu trách nhiệm ECR repository + GitHub OIDC Federation provider.

**File ảnh hưởng:** `CLAUDE.md` mục 5, `terraform-structure.md` mục 2

---

### Q6 — Stub module `analytics/`

Tạo `infra/modules/analytics/README.md` (chỉ file README, không có `.tf`) với nội dung ghi rõ: *"Reserved for Phase 6 (Glue / Athena / QuickSight)"*. Mục đích: cấu trúc thư mục tổng thể không bị đổi giữa chừng khi tới Phase 6.

**File ảnh hưởng:** `CLAUDE.md` mục 5, `terraform-structure.md` mục 3

---

### Q7 — Pin version

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
```

Khai báo trong `versions.tf` của **mỗi module** và mỗi environment.

**File ảnh hưởng:** `terraform-structure.md` mục 8

---

### Q8 — Terraform remote backend

| Thành phần | Giá trị |
|---|---|
| Region | `ap-southeast-1` (Singapore) — áp dụng cho toàn bộ dự án |
| State bucket | `matchlens-terraform-state-{aws_account_id}` |
| Lock table | `matchlens-terraform-locks` |
| State key | `environments/{env}/terraform.tfstate` |

Bucket bật versioning + encryption + block public access. Tạo 1 lần duy nhất qua `infra/global/bootstrap/` bằng local state, sau đó migrate state của chính bootstrap lên S3.

**File ảnh hưởng:** `terraform-structure.md` mục 5.1

---

### Q9 — Tag `Owner`

Giá trị chính xác, không đổi: `Owner = "luong-van-vo"`. Truyền qua biến `owner` trong `terraform.tfvars` của từng environment, không hardcode trong module.

**File ảnh hưởng:** `naming-tagging-standard.md` mục 3.1

---

### Q10 — `status` (DB) vs `processing_status` (API)

| Tầng | Tên field |
|---|---|
| Cột DB / Prisma model | `status` |
| API request/response DTO | `processing_status` |

**5 giá trị hợp lệ, đồng bộ cả 2 tầng:** `pending`, `uploaded`, `processing`, `completed`, `failed`.

**File ảnh hưởng:** `api-design.md` mục 6, `database-schema.md` mục 2.4 + mục 3

---

### Q11 — ResourceOwnershipGuard cho route chỉ có `:match_id`

Với các endpoint không có `:team_id` trong path (`/matches/{match_id}/upload-url`, `/confirm-upload`, `/status`, `/highlights`, `/stats`, `DELETE /matches/{match_id}`, `/track-mappings`):

1. Guard đọc `match_id` từ `request.params`
2. Query bằng **`prisma.write` (Master client)** — không dùng `prisma.read`
3. Lấy `match.team_id` → `team.owner_id`
4. Cho qua nếu `team.owner_id === request.user.id` **hoặc** `request.user.role === 'admin'`
5. Ngược lại → `403 FORBIDDEN`

**Lý do bắt buộc dùng Master:** kiểm tra phân quyền đọc từ Read Replica có replication lag sẽ gây `403` oan ngay sau khi user vừa tạo team/match. Đây là ngoại lệ có chủ đích của quy tắc "đọc thì dùng replica".

**File ảnh hưởng:** `backend-architecture.md` mục 7, `api-design.md` mục 8

---

### Q12 — Bảng `refresh_tokens`

Thêm bảng mới vào RDS để `POST /v1/auth/logout` revoke được token:

| Cột | Kiểu | Ràng buộc |
|---|---|---|
| `id` | `UUID` | PK |
| `user_id` | `UUID` | FK → `users.id` `ON DELETE CASCADE` |
| `token_hash` | `VARCHAR(255)` | `NOT NULL` — lưu hash, **không lưu token thô** |
| `expires_at` | `TIMESTAMPTZ` | `NOT NULL` |
| `revoked_at` | `TIMESTAMPTZ` | `NULL` = còn hiệu lực |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL DEFAULT now()` |

**File ảnh hưởng:** `database-schema.md` mục 2.5 (mới) + mục 4, `api-design.md` mục 3

---

### Q13 — snake_case ở API, camelCase trong code

- DTO request/response: **snake_case** (giữ đúng `api-design.md`)
- Biến/property TypeScript: **camelCase**
- Cơ chế mapping: `ClassSerializerInterceptor` + `@Expose({ name: 'snake_case_name' })` của `class-transformer`

**Thứ tự interceptor bắt buộc** (xem D5): `ClassSerializerInterceptor` chạy trước (map tên field), `ResponseTransformInterceptor` bọc `{success, data, error}` sau.

**File ảnh hưởng:** `backend-architecture.md` mục 2 + mục 11 (mới)

---

### Q14 — JWT payload key

- Trong **payload JWT**: `user_id`
- Sau khi `JwtStrategy.validate()`: gắn vào `request.user.id`

Nhờ vậy controller/guard viết `request.user.id` tự nhiên, còn token vẫn giữ đúng convention snake_case của API.

**File ảnh hưởng:** `api-design.md` mục 2.2, `backend-architecture.md` mục 7

---

### Q15 — Node 22 + Prisma 6

| Thành phần | Version |
|---|---|
| Base image | `node:22-alpine` |
| Prisma | `~> 6.0` |

Prisma 6 dùng cú pháp **`datasourceUrl`** (số ít, string) thay cho `datasources: { db: { url } }` của Prisma 5:

```typescript
this.write = new PrismaClient({ datasourceUrl: process.env.DATABASE_URL_MASTER });
this.read  = new PrismaClient({ datasourceUrl: process.env.DATABASE_URL_REPLICA });
```

**File ảnh hưởng:** `backend-architecture.md` mục 4.2 + mục 8

---

### Q16 — HealthModule ngay Phase 0

`GET /health` trả về:

```json
{ "status": "ok", "db": "up", "timestamp": "2026-08-03T10:00:00Z" }
```

Dùng cho ALB Target Group Health Check và ECS container health check. Endpoint này **không qua JwtAuthGuard** và **không qua ResponseTransformInterceptor** (ALB cần response phẳng, không bọc wrapper).

**File ảnh hưởng:** `backend-architecture.md` mục 2 + mục 9, `api-design.md` mục 7

---

### Q17 — Module `players/` riêng

`src/players/` là NestJS module độc lập (controller + service + dto riêng), không gộp vào `teams/`.

**File ảnh hưởng:** `CLAUDE.md` mục 5

---

## GROUP B — Phase 1 Blockers (Highlight Engine & Worker)

### Q18 + Q19 — S3 key layout (bỏ prefix trùng tên bucket, bắt buộc có `{team_id}`)

Prefix trùng tên bucket bị loại bỏ hoàn toàn (`s3://matchlens-dev-raw-videos/raw-videos/...` → sai). Mọi path bắt buộc có `{team_id}` để IAM policy condition theo prefix dùng được đồng đều.

| Bucket | Object key |
|---|---|
| `matchlens-{env}-raw-videos` | `{team_id}/{match_id}/original.mp4` |
| `matchlens-{env}-processed-highlights` | `raw-clips/{team_id}/{match_id}/{event_id}.mp4` (Worker ghi)<br>`clips/{team_id}/{match_id}/{event_id}.mp4` (MediaConvert ghi) |
| `matchlens-{env}-raw-tracking-data` | `{team_id}/{match_id}/tracking_batch_{batch_number}.json` |
| `matchlens-{env}-curated-data` | `team_id={team_id}/match_id={match_id}/player_stats.parquet`<br>`team_id={team_id}/match_id={match_id}/heatmap_data.parquet` |

**`curated-data` dùng Hive-style partitioning** (`key=value/`) — để Glue Crawler tự nhận `team_id` và `match_id` thành partition column, và Athena query được `WHERE team_id = '...'` mà không scan toàn bộ bucket (giảm cả độ trễ lẫn chi phí).

**File ảnh hưởng:** `data-model.md` mục 3.2, `data-contracts.md` mục 3.1 + 4.1 + 4.2, `backend-architecture.md` mục 5

---

### Q19b — Chống vòng lặp S3 Event → MediaConvert → S3 Event

Trong cùng bucket `processed-highlights`, tách **2 prefix gốc khác nhau**:

```
raw-clips/{team_id}/{match_id}/{event_id}.mp4    ← Worker ghi (INPUT)
clips/{team_id}/{match_id}/{event_id}.mp4        ← MediaConvert ghi (OUTPUT)
```

S3 Event Notification cấu hình **`filter_prefix = "raw-clips/"`**. Vì MediaConvert ghi vào `clips/` — không khớp filter — nên không thể tự kích hoạt lại chính nó. Đây là biện pháp chống đệ quy ở tầng kiến trúc, không phụ thuộc vào logic trong Lambda.

**Quy tắc bổ sung:** `highlight_clip_s3_key` trong DynamoDB lưu đường dẫn **bản transcode** (`clips/...`), dù Worker ghi record này trước khi MediaConvert chạy xong. Điều này hợp lệ vì key là **tất định** (dẫn xuất từ `event_id`), Worker biết trước MediaConvert sẽ ghi ra đâu. Backend chỉ trả `/highlights` khi `status = 'completed'`, nên thời điểm client nhận link thì file đã tồn tại.

**File ảnh hưởng:** `data-contracts.md` mục 2.2, `data-model.md` mục 3.2, `system-flows.md` mục 3

---

### Q20 — Cập nhật `matches.status` qua Event-Driven Callback

**Không** cấp RDS credential cho AI Worker hay Lambda Job Dispatcher. Thêm 2 resource mới:

| Resource | Tên | Vai trò |
|---|---|---|
| SQS Queue | `matchlens-{env}-match-status-callbacks` | Nhận message báo đổi trạng thái |
| SQS DLQ | `matchlens-{env}-match-status-callbacks-dlq` | Bắt callback lỗi (xem D2) |
| Lambda | `matchlens-{env}-status-updater-fn` | **Thành phần compute duy nhất ngoài Backend có RDS write credential** |

**Message schema:**

```json
{
  "match_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "processing",
  "reason": null,
  "duration_sec": null,
  "emitted_at": "2026-08-03T10:45:23Z"
}
```

| Field | Bắt buộc | Ghi chú |
|---|---|---|
| `match_id` | Có | UUID |
| `status` | Có | Một trong `processing`, `completed`, `failed` |
| `reason` | Không | Bắt buộc có giá trị khi `status = "failed"` → ghi vào `matches.error_message` |
| `duration_sec` | Không | Worker báo độ dài video khi `status = "completed"` → ghi vào `matches.duration_sec` |
| `emitted_at` | Có | ISO 8601 |

**Phân chia quyền ghi status (quyết định chốt):**

| Transition | Ai ghi |
|---|---|
| `→ pending` (tạo match) | Backend NestJS, `prisma.write` |
| `pending → uploaded` (confirm-upload) | Backend NestJS, `prisma.write` |
| `uploaded → processing` | `status-updater-lambda` (do Job Dispatcher gửi callback) |
| `processing → completed` | `status-updater-lambda` (do AI Worker gửi callback) |
| `processing → failed` | `status-updater-lambda` (do AI Worker gửi callback, hoặc DLQ alarm) |

**Hệ quả đã chấp nhận:** logic validate state machine tồn tại ở **2 nơi** — `backend/src/matches/status-transition.ts` (TypeScript) và `lambdas/status_updater/transitions.py` (Python). Cả 2 phải giữ đồng bộ; khi sửa 1 bên bắt buộc sửa bên còn lại. Đánh đổi này được chấp nhận để `confirm-upload` phản hồi tức thì cho UI (nếu đẩy qua queue thì phải trả `202 Accepted` và client phải poll).

**File ảnh hưởng:** `system-flows.md` mục 3, `terraform-structure.md` mục 3.5, `iam-security-design.md` mục 2 + 3, `database-schema.md` mục 3

---

### Q21 — Quyền Worker + MediaConvert qua Lambda riêng

**Bổ sung cho `worker-role`:** `dynamodb:GetItem`, `dynamodb:Query` (cần cho idempotency check ở Q22).

**AI Worker KHÔNG gọi MediaConvert trực tiếp.** Luồng transcode:

```
Worker ghi raw-clips/{team_id}/{match_id}/{event_id}.mp4
   │
   ▼  S3 Event Notification (filter_prefix = "raw-clips/")
matchlens-{env}-mediaconvert-trigger-fn  (Lambda)
   │  CreateJob + PassRole
   ▼
MediaConvert  (chạy dưới matchlens-{env}-mediaconvert-role)
   │
   ▼
clips/{team_id}/{match_id}/{event_id}.mp4
```

Hai IAM role mới: `matchlens-{env}-mediaconvert-trigger-role` (Lambda: `mediaconvert:CreateJob` + `iam:PassRole` giới hạn đúng 1 role) và `matchlens-{env}-mediaconvert-role` (service role của MediaConvert: đọc `raw-clips/*`, ghi `clips/*`).

**File ảnh hưởng:** `iam-security-design.md` mục 2 + 3.2 + 3.6 + 3.7, `system-flows.md` mục 3, `terraform-structure.md` mục 3.5

---

### Q22 — Idempotency: marker + `event_id` tất định

**Hai cơ chế kết hợp:**

**(1) Completion marker.** Worker khi nhận job SQS:
- `GetItem` với `match_id` = từ message, `event_id` = `"MARKER#COMPLETED"`
- Nếu **tồn tại** → job này đã hoàn thành trước đó → xoá message SQS ngay, không xử lý lại
- Nếu **không tồn tại** → chạy inference, ghi toàn bộ event, **ghi marker ở bước cuối cùng**

**(2) `event_id` tất định (thay ULID random).**

```python
ts_ms  = int(timestamp_in_video * 1000)
hash10 = sha256(f"{match_id}|{timestamp_in_video}|{event_type}".encode()).hexdigest()[:10]
event_id = f"{ts_ms:013d}-{hash10}"     # ví dụ: "0000000342500-9f2a1c7e4b"
```

**Lý do bắt buộc phải tất định:** với ULID random, mỗi lần retry sinh khóa hoàn toàn mới → `PutItem` không overwrite → crash giữa đường (đã ghi 3/50 event) khiến lần chạy lại tạo thêm 50 item, tổng 53 → HLV thấy 3 highlight lặp. Khóa tất định đảm bảo cùng sự kiện → cùng khóa → `PutItem` overwrite thật sự, nên retry an toàn ở mọi thời điểm crash.

**Vẫn sort được theo thời gian** (yêu cầu gốc của Sort Key) vì 13 chữ số đầu là timestamp zero-padded, sort lexicographic tương đương sort số.

**File ảnh hưởng:** `data-contracts.md` mục 2.2 + 2.4 (mới), `iam-security-design.md` mục 3.2

---

### Q23 — CloudFront Signed URL + OAC

- S3 `processed-highlights` là **private hoàn toàn**, chỉ CloudFront truy cập được qua **Origin Access Control (OAC)**
- Backend sinh **CloudFront Signed URL**, hiệu lực **4 giờ**
- Private key ký URL lưu ở Secrets Manager: `matchlens-{env}-cloudfront-signing-key-secret`
- Terraform tạo `aws_cloudfront_public_key` + `aws_cloudfront_key_group`

**Hệ quả thu hẹp quyền (least-privilege tốt hơn):** `backend-role` **bỏ** `s3:GetObject` trên `processed-highlights` — không còn cần khi dùng OAC + signed URL. Thay bằng quyền đọc secret chứa signing key.

**File ảnh hưởng:** `iam-security-design.md` mục 3.1 + mục 4, `api-design.md` mục 6, `data-model.md` mục 3.2, `terraform-structure.md` mục 3.4

---

### Q24 — `position_field` giữ chuẩn hóa 0–100 + thêm `field_dimensions`

`position_field` **giữ nguyên hệ chuẩn hóa `x: 0–100`, `y: 0–100`** như contract gốc. Bổ sung field `field_dimensions` ở root JSON để ETL biết chính xác hệ số quy đổi ra mét:

```json
{
  "schema_version": 1,
  "match_id": "...",
  "field_dimensions": { "length_m": 105, "width_m": 68 },
  "frames": [ ... ]
}
```

Glue ETL quy đổi:

```python
x_m = position_field["x"] * (field_dimensions["length_m"] / 100)
y_m = position_field["y"] * (field_dimensions["width_m"]  / 100)
```

**Lý do chọn cách này:** sân bóng phong trào thường không đúng chuẩn 105×68m. Ghi kèm kích thước thật vào chính file dữ liệu khiến JSON **tự mô tả** (self-describing) — ETL không phải giả định hằng số, và dữ liệu cũ vẫn tính đúng nếu sau này xử lý sân kích thước khác.

**Phương pháp tính `position_field` ở v1 — Fixed Static Tactical Camera:**
- Giả định camera tĩnh, góc quay cố định suốt trận
- Cấu hình 4 điểm mốc sân (field anchor points) đã biết cho mỗi video
- Dùng OpenCV `cv2.findHomography` + `cv2.perspectiveTransform` để project tọa độ pixel bbox → tọa độ sân
- Chuẩn hóa kết quả về 0–100 trước khi ghi JSON

Giới hạn này **phải ghi rõ trong `README.md`** phần Worker.

**File ảnh hưởng:** `data-contracts.md` mục 3.2 + 3.3, `README.md`

---

### Q25 — Không OCR số áo; dùng `track_id` + mapping thủ công

**v1 không nhận diện số áo.** YOLOv11 kết hợp thuật toán tracking (**ByteTrack** hoặc **BoT-SORT**) sinh ID số nguyên bền vững trong suốt 1 trận: `track_id`.

| Field | Giá trị ở v1 |
|---|---|
| `track_id` | **Bắt buộc**, integer, do tracker sinh (Track #1, #2, ...) |
| `team_side` | Bắt buộc, `"home"` / `"away"` |
| `player_id` | **Luôn `null`** ở v1 (giữ field cho tương lai) |
| `jersey_number` | **Luôn `null`** ở v1 |

`track_id` phải được thêm vào: JSON tracking (`data-contracts.md` mục 3.2), `player_stats.parquet` và `heatmap_data.parquet` (mục 4). **Hai file Parquet khóa theo `track_id`, không phải `player_id`.**

**Mapping ở Phase 6:** Frontend hiển thị "Player Track #1 (Home)" kèm dropdown cho HLV gán `Track #1 → [Quang Hải]`. Backend lưu vào bảng RDS mới `match_track_mappings` (xem D1). Dashboard join `track_id → player_id → players.full_name` để hiển thị tên thật.

**File ảnh hưởng:** `data-contracts.md` mục 3.2 + 4.1 + 4.2 + 5, `database-schema.md` mục 2.6 (mới), `api-design.md` mục 6

---

### Q26 — `schema_version`

Thêm `"schema_version": 1` ở **root** của mọi file JSON tracking Worker ghi ra S3. Glue ETL đọc field này và fail-fast với message rõ ràng nếu gặp version chưa hỗ trợ (thay vì crash với lỗi khó hiểu ở giữa job).

**File ảnh hưởng:** `data-contracts.md` mục 3.2

---

### Q27 — Giữ `confirm-upload`

`POST /v1/matches/{match_id}/confirm-upload` là **bắt buộc**, không bỏ. Đây là trigger chính xác cho transition `pending → uploaded`, do Backend ghi trực tiếp (đồng bộ, phản hồi tức thì cho UI). Sau đó S3 Event → Job Dispatcher mới đẩy tiếp sang `processing`.

**File ảnh hưởng:** `api-design.md` mục 6 + 9, `database-schema.md` mục 3

---

### Q28 — Cấu hình SQS + validate upload

| Tham số | Giá trị |
|---|---|
| `max_receive_count` | `3` (vượt → DLQ) |
| `visibility_timeout` | `900` giây (15 phút) — phải lớn hơn thời gian YOLO inference 1 video, tránh redeliver khi job vẫn đang chạy |
| Giới hạn file upload | `2147483648` bytes (2 GB) |
| `content_type` cho phép | `video/mp4`, `video/quicktime` |
| Presigned URL TTL | `900` giây (15 phút) |

**File ảnh hưởng:** `api-design.md` mục 6, `terraform-structure.md` mục 3.5

---

## GROUP C — Optimizations & FinOps

### Q29 — VPC Gateway Endpoint ngay Phase 0

Tạo **Gateway Endpoint** (miễn phí) cho:
- `com.amazonaws.ap-southeast-1.s3`
- `com.amazonaws.ap-southeast-1.dynamodb`

Gắn vào route table của Private App Subnet. Traffic ECS → S3 (upload/download hàng GB video) và ECS → DynamoDB **không đi qua NAT Instance** → tiết kiệm data transfer đáng kể và tăng bảo mật (traffic không ra internet).

**Lưu ý:** Secrets Manager **không có** Gateway Endpoint, chỉ có Interface Endpoint (~$7/AZ/tháng). Ở dev, traffic tới Secrets Manager đi qua NAT Instance (đã có, $0 thêm). Interface Endpoint là tùy chọn cân nhắc cho prod.

**File ảnh hưởng:** `architecture.md` mục 2, `terraform-structure.md` mục 3.1, `iam-security-design.md` mục 7

---

### Q30 — Bucket thứ 5: `athena-results`

`matchlens-{env}-athena-results` — nơi Athena ghi kết quả query (Athena bắt buộc phải có S3 location này).

- Lifecycle rule: **xoá vĩnh viễn sau 7 ngày**
- `backend-role` cần `s3:PutObject` + `s3:GetObject` + `s3:ListBucket` trên bucket này (Athena ghi dưới danh nghĩa caller)

Tổng số bucket của hệ thống: **5**.

**File ảnh hưởng:** `data-model.md` mục 3.2, `naming-tagging-standard.md` mục 2.2, `terraform-structure.md` mục 3.4, `iam-security-design.md` mục 3.1 + 3.4

---

### Q31 — Không render PNG heatmap ở server

`GET /v1/matches/{match_id}/stats` trả **mảng số thô**, frontend tự vẽ:

```json
{
  "track_id": 1,
  "team_side": "home",
  "player_id": null,
  "distance_covered_km": 8.4,
  "avg_speed_kmh": 7.2,
  "max_speed_kmh": 24.1,
  "heatmap": [
    { "x": 5, "y": 3, "intensity": 85 }
  ]
}
```

React render heatmap tương tác bằng HTML5 Canvas (hoặc thư viện chart) đè lên hình ảnh sân. Field `heatmap_url` (PNG) bị **loại bỏ** khỏi spec — không có thành phần nào trong hệ thống sinh ảnh PNG.

**File ảnh hưởng:** `api-design.md` mục 6, `data-contracts.md` mục 4.2

---

### Q32 — Lưới heatmap 10 × 6

| Trục | Số ô | Kích thước mỗi ô (sân 105×68m) |
|---|---|---|
| x (chiều dài) | **10** | 10.5 m |
| y (chiều rộng) | **6** | ~11.3 m |

Tổng 60 vùng chiến thuật. `position_x_bucket` ∈ [0, 9], `position_y_bucket` ∈ [0, 5].

Công thức trong ETL (từ `position_field` chuẩn hóa 0–100):

```python
x_bucket = min(int(position_field["x"] / 10),      9)   # 100 / 10 buckets
y_bucket = min(int(position_field["y"] / (100/6)), 5)   # 100 /  6 buckets
```

`min()` để chặn edge case tọa độ đúng bằng 100 tràn ra khỏi mảng.

**File ảnh hưởng:** `data-contracts.md` mục 4.2

---

### Q33 — Các chuẩn kỹ thuật mở

| Hạng mục | Quyết định |
|---|---|
| **JWT** | **RS256** (asymmetric). Keypair lưu ở Secrets Manager `matchlens-{env}-jwt-keypair-secret` dạng JSON `{ "private_key_pem": "...", "public_key_pem": "..." }`. Xem D3 |
| **Logging** | **Pino** (`nestjs-pino`) — JSON structured log, tối ưu cho CloudWatch Log Insights |
| **Rate limiting** | `@nestjs/throttler`, **10 req/phút/user** trên `POST /matches/{match_id}/upload-url` |
| **Budget Alert** | **$50/tháng** (xem lý do bên dưới): 50% = $25 cảnh báo, 80% = $40 rà soát resource, 100% = $50 cân nhắc destroy dev |
| **Auto-shutdown dev** | EventBridge Schedule cron `0 17 * * ? *` UTC (= 00:00 giờ VN): scale ECS Fargate desired count → `0`, **stop** RDS instance. Xem D4 |

**Lý do budget là $50 chứ không phải $15:** sàn cứng của hạ tầng dev chạy 24/7 đã là ~$32–39/tháng và **auto-shutdown không giảm được phần này**:

| Thành phần | Chi phí/tháng | Auto-shutdown có giúp? |
|---|---|---|
| ALB | ~$16–18 | ❌ Tính phí theo giờ tồn tại, không theo task ECS |
| NAT Instance t3.micro | ~$8–10 | ❌ Trừ khi stop cả EC2 instance |
| RDS storage 20GB gp3 | ~$2–3 | ❌ RDS stopped vẫn tính phí storage |
| WAF Web ACL | ~$6–8 | ❌ Phí cố định theo Web ACL |

Đặt $15 sẽ khiến alarm bắn 100% ngay tuần đầu và trở thành cảnh báo vô nghĩa. $50 khớp với con số "thực tế $30–50" đã ghi ở `cost-estimate.md` mục 3, giữ được hạ tầng đầy đủ (ALB + WAF + CloudFront) để portfolio thể hiện đúng kiến trúc production.

**File ảnh hưởng:** `iam-security-design.md` mục 4 + 7, `backend-architecture.md` mục 9, `cost-estimate.md` mục 5 + 6, `api-design.md` mục 9

---

### Q34 — Cập nhật cost-estimate

Read Replica (~$14/tháng) chỉ tính cho `staging`/`prod`. Môi trường `dev` giữ baseline tối ưu (không Replica, 1 NAT, Single-AZ). Bổ sung thêm dòng ECR storage và bucket `athena-results` vào bảng ước tính.

**File ảnh hưởng:** `cost-estimate.md` mục 2.2 + 3

---

## Quyết định hệ quả phát sinh khi áp dụng (D1–D5)

### D1 — Bảng `match_track_mappings`

Q25 yêu cầu lưu mapping `track_id → player_id` vào RDS nhưng chưa có bảng. Thêm:

| Cột | Kiểu | Ràng buộc |
|---|---|---|
| `id` | `UUID` | PK |
| `match_id` | `UUID` | FK → `matches.id` `ON DELETE CASCADE` |
| `track_id` | `INTEGER` | `NOT NULL` — ID do tracker sinh |
| `player_id` | `UUID` | `NULL`, FK → `players.id` `ON DELETE SET NULL` — `NULL` = HLV chưa gán |
| `team_side` | `VARCHAR(10)` | `NOT NULL`, `CHECK (team_side IN ('home','away'))` |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | `NOT NULL DEFAULT now()` |

**Ràng buộc:** `UNIQUE (match_id, track_id)` — 1 track chỉ map 1 lần trong 1 trận.

Endpoint kèm theo: `PUT /v1/matches/{match_id}/track-mappings`.

---

### D2 — DLQ cho queue callback

`match-status-callbacks` phải có DLQ riêng (`matchlens-{env}-match-status-callbacks-dlq`, `max_receive_count = 3`) + CloudWatch Alarm.

**Lý do:** nếu `status-updater-lambda` chết (RDS unreachable, bug transition validation), status của match sẽ **treo ở `processing` vĩnh viễn** mà không ai biết — user thấy spinner quay mãi. Đây là silent failure nguy hiểm hơn cả job xử lý AI thất bại.

---

### D3 — Tách secret JWT thành keypair

RS256 cần cả private key (ký) và public key (verify). Secret `matchlens-{env}-jwt-secret` (tên cũ, dành cho HS256) được **đổi tên** thành `matchlens-{env}-jwt-keypair-secret`, nội dung JSON 2 field. Rotation vẫn thủ công (đổi keypair invalidate toàn bộ session đang hoạt động).

---

### D4 — RDS không có "pause", chỉ có "stop"

Thuật ngữ "pause" chỉ áp dụng cho Aurora Serverless. RDS PostgreSQL instance thường chỉ có **stop**, và **AWS tự động start lại sau tối đa 7 ngày**.

Vì vậy auto-shutdown dev cần **2 EventBridge rule**, không phải 1:
- `0 17 * * ? *` UTC (00:00 VN) → ECS desired count = 0, `StopDBInstance`
- `0 1 * * ? *` UTC (08:00 VN) → `StartDBInstance`, ECS desired count = 1

Ngoài ra: RDS stopped **vẫn tính phí storage**, và không thể stop instance đang có Read Replica — nên rule này chỉ áp dụng cho `dev` (nơi không có Replica theo Q3).

---

### D5 — Thứ tự interceptor + ngoại lệ marker

**(a) Thứ tự interceptor** (Q13 + `api-design.md` mục 1): `ClassSerializerInterceptor` chạy **trước** (map camelCase → snake_case), `ResponseTransformInterceptor` bọc `{success, data, error}` **sau**. `/health` được loại khỏi cả hai.

**(b) Item `MARKER#COMPLETED` là ngoại lệ được đặc tả của DynamoDB contract.** Nó chỉ có `match_id` + `event_id` + `created_at`, **thiếu** các attribute vốn là bắt buộc (`event_type`, `timestamp_in_video`, `highlight_clip_s3_key`, `confidence_score`).

→ **Backend `GET /highlights` BẮT BUỘC filter bỏ mọi item có `event_id` bắt đầu bằng `"MARKER#"`.** Nếu quên, HLV sẽ thấy 1 highlight rỗng không phát được. Glue ETL đọc DynamoDB (nếu có) cũng phải áp dụng filter tương tự.

---

## Bảng tra cứu nhanh — resource mới phát sinh so với thiết kế gốc

| Loại | Tên | Từ quyết định |
|---|---|---|
| S3 Bucket | `matchlens-{env}-athena-results` | Q30 |
| SQS Queue | `matchlens-{env}-match-status-callbacks` | Q20 |
| SQS DLQ | `matchlens-{env}-match-status-callbacks-dlq` | D2 |
| Lambda | `matchlens-{env}-status-updater-fn` | Q20 |
| Lambda | `matchlens-{env}-mediaconvert-trigger-fn` | Q21 |
| IAM Role | `matchlens-{env}-status-updater-role` | Q20 |
| IAM Role | `matchlens-{env}-mediaconvert-trigger-role` | Q21 |
| IAM Role | `matchlens-{env}-mediaconvert-role` | Q21 |
| Secret | `matchlens-{env}-jwt-keypair-secret` (đổi tên) | Q33, D3 |
| Secret | `matchlens-{env}-cloudfront-signing-key-secret` | Q23 |
| VPC Endpoint | S3 + DynamoDB Gateway Endpoint | Q29 |
| CloudFront | `aws_cloudfront_public_key` + `key_group` | Q23 |
| RDS table | `refresh_tokens` | Q12 |
| RDS table | `match_track_mappings` | D1, Q25 |
| Subnet tier | Private DB Subnet (tier thứ 3) | Q1 |
| EventBridge | 2 rule stop/start dev | Q33, D4 |

---

## Quy tắc duy trì file này

1. Mỗi quyết định kiến trúc mới phát sinh trong lúc code → thêm mục vào file này **trước**, rồi mới sửa file `docs/` liên quan, rồi mới code
2. Không sửa quyết định đã chốt mà không ghi lại lý do đổi + ngày đổi
3. Khi code trái với file này → code sai, không phải file sai (trừ khi đã qua bước 1)
