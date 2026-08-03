# MatchLens — API Design

> Thiết kế chi tiết toàn bộ API của hệ thống, dựa trên Data Model (`docs/data-model.md`) và System Flows (`docs/system-flows.md`) đã chốt. Phạm vi hiện tại: tính năng lõi theo từng trận đấu (upload, highlight, phân tích chỉ số trong 1 trận). Chưa bao gồm endpoint tổng hợp nhiều trận/mùa giải — sẽ bổ sung ở giai đoạn mở rộng sau.

---

## 1. Nguyên tắc thiết kế chung

- REST API, version hóa ngay từ đầu: tất cả endpoint có prefix `/v1/`
- **Convention naming:** request/response DTO dùng **snake_case**; biến trong code TypeScript dùng **camelCase**. Mapping qua `ClassSerializerInterceptor` + `@Expose({ name: '...' })` của `class-transformer` (quyết định Q13)
- Response format thống nhất dạng JSON, có wrapper chung để dễ xử lý lỗi ở frontend:
```json
{
  "success": true,
  "data": { },
  "error": null
}
```
- Lỗi trả về theo format:
```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Mô tả lỗi cụ thể"
  }
}
```
- **Thứ tự interceptor bắt buộc** (quyết định D5): `ClassSerializerInterceptor` chạy **trước** (map camelCase → snake_case), `ResponseTransformInterceptor` bọc wrapper `{success, data, error}` **sau**. Endpoint `/health` được loại khỏi cả hai (ALB cần response phẳng)
- Auth: JWT Bearer Token, gửi qua header `Authorization: Bearer {token}`, thuật toán **RS256** (asymmetric — quyết định Q33)
- Toàn bộ endpoint (trừ `/auth/*` và `/health`) yêu cầu token hợp lệ
- Dùng UUID cho toàn bộ resource ID, đồng bộ với Data Model

---

## 2. Auth Flow chi tiết

### 2.1. Luồng đăng ký/đăng nhập

```
POST /v1/auth/register  → tạo user mới, hash password bằng bcrypt
POST /v1/auth/login     → trả về access_token + refresh_token
POST /v1/auth/refresh   → dùng refresh_token để lấy access_token mới
POST /v1/auth/logout    → vô hiệu hóa refresh_token hiện tại
```

### 2.2. Chi tiết token
- `access_token`: JWT **RS256**, thời hạn ngắn (30 phút), dùng cho mọi request
- `refresh_token`: thời hạn 7 ngày, **hash SHA-256 lưu vào bảng RDS `refresh_tokens`** để có thể revoke khi logout (quyết định Q12)
- Payload JWT tối thiểu: `{ user_id, email, role, exp }` — dùng key **`user_id`** trong payload (quyết định Q14)
- Keypair RS256 lưu ở Secrets Manager `matchlens-{env}-jwt-keypair-secret` dạng `{ private_key_pem, public_key_pem }` (quyết định D3)

### 2.3. Middleware xác thực
Mọi endpoint (trừ `/auth/*` và `/health`) đi qua guard kiểm tra:
1. Token có tồn tại trong header không
2. Token còn hạn, chữ ký RS256 hợp lệ không (verify bằng public key)
3. Gắn `user_id` từ payload vào **`request.user.id`** để controller/guard dùng syntax tự nhiên (quyết định Q14)

---

## 3. Endpoints — Authentication

### `POST /v1/auth/register`
**Request:**
```json
{
  "email": "coach@example.com",
  "password": "string (min 8 ký tự)",
  "full_name": "Nguyen Van A"
}
```
**Response 201:**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "email": "coach@example.com",
    "full_name": "Nguyen Van A"
  }
}
```
**Lỗi có thể:** `EMAIL_ALREADY_EXISTS` (409), `VALIDATION_ERROR` (400)

---

### `POST /v1/auth/login`
**Request:**
```json
{
  "email": "coach@example.com",
  "password": "string"
}
```
**Response 200:**
```json
{
  "success": true,
  "data": {
    "access_token": "jwt-string",
    "refresh_token": "jwt-string",
    "expires_in": 1800
  }
}
```
**Lỗi có thể:** `INVALID_CREDENTIALS` (401)

---

### `POST /v1/auth/refresh`
**Request:**
```json
{ "refresh_token": "jwt-string" }
```
**Response 200:** giống response của `/login` (cấp lại cặp token mới)

**Xử lý phía Backend:** hash token nhận được → tra `refresh_tokens.token_hash` → kiểm tra `revoked_at IS NULL` và `expires_at > now()`. Cấp cặp token mới và **revoke token cũ** (rotation).

**Lỗi có thể:** `INVALID_REFRESH_TOKEN` (401)

---

### `POST /v1/auth/logout`
Revoke refresh token hiện tại (quyết định Q12 — cần bảng `refresh_tokens` để làm được việc này).

**Request:**
```json
{ "refresh_token": "jwt-string" }
```
**Response 200:**
```json
{
  "success": true,
  "data": { "message": "Đăng xuất thành công" }
}
```
**Xử lý:** set `revoked_at = now()` cho row tương ứng `token_hash`. Access token còn lại vẫn hợp lệ tới khi hết hạn (tối đa 30 phút) — đây là đánh đổi cố hữu của JWT stateless, chấp nhận được.

**Lỗi có thể:** `INVALID_REFRESH_TOKEN` (401)

---

### `GET /health`
Health check cho ALB Target Group và ECS container check (quyết định Q16). **Không có prefix `/v1/`**, không cần auth, **không bọc response wrapper**.

**Response 200:**
```json
{ "status": "ok", "db": "up", "timestamp": "2026-08-03T10:00:00Z" }
```
Trả `503` nếu không kết nối được DB (`"db": "down"`) để ALB đưa task ra khỏi rotation.

---

## 4. Endpoints — Teams

### `POST /v1/teams`
Tạo đội mới, `owner_id` lấy từ token, không cần client gửi lên.

**Request:**
```json
{ "name": "FC Đà Nẵng Amateur" }
```
**Response 201:**
```json
{
  "success": true,
  "data": {
    "team_id": "uuid",
    "name": "FC Đà Nẵng Amateur",
    "owner_id": "uuid",
    "created_at": "2026-07-31T10:00:00Z"
  }
}
```

---

### `GET /v1/teams`
Danh sách đội thuộc về user hiện tại (dựa vào `owner_id` từ token).

**Response 200:**
```json
{
  "success": true,
  "data": [
    { "team_id": "uuid", "name": "FC Đà Nẵng Amateur", "created_at": "..." }
  ]
}
```

---

### `GET /v1/teams/{team_id}`
Chi tiết 1 đội. **Yêu cầu kiểm tra quyền sở hữu** — nếu `team.owner_id != user_id` từ token → trả `403 FORBIDDEN`.

---

## 5. Endpoints — Players

### `POST /v1/teams/{team_id}/players`
**Request:**
```json
{
  "full_name": "Nguyen Van B",
  "jersey_number": 10,
  "position": "forward"
}
```
**Response 201:** trả về object player vừa tạo (bao gồm `player_id`)

---

### `GET /v1/teams/{team_id}/players`
Danh sách cầu thủ của 1 đội.

### `PUT /v1/teams/{team_id}/players/{player_id}`
Cập nhật thông tin cầu thủ.

### `DELETE /v1/teams/{team_id}/players/{player_id}`
Xóa cầu thủ (cân nhắc soft-delete theo câu hỏi mở ở Data Model).

---

## 6. Endpoints — Matches (nhóm quan trọng nhất)

### `POST /v1/teams/{team_id}/matches`
Tạo trận đấu mới (chưa có video).

**Request:**
```json
{
  "opponent_name": "FC Hải Châu",
  "match_date": "2026-08-05"
}
```
**Response 201:**
```json
{
  "success": true,
  "data": {
    "match_id": "uuid",
    "team_id": "uuid",
    "opponent_name": "FC Hải Châu",
    "match_date": "2026-08-05",
    "processing_status": "pending",
    "video_s3_key": null
  }
}
```

---

### `POST /v1/matches/{match_id}/upload-url`
Sinh presigned URL để client upload trực tiếp lên S3 (theo đúng luồng đã thiết kế ở System Flows mục 2).

**Request:**
```json
{
  "file_name": "match_2026_08_05.mp4",
  "content_type": "video/mp4",
  "file_size_bytes": 524288000
}
```
**Response 200:**
```json
{
  "success": true,
  "data": {
    "upload_url": "https://matchlens-dev-raw-videos.s3.ap-southeast-1.amazonaws.com/...",
    "s3_key": "{team_id}/{match_id}/original.mp4",
    "expires_in": 900
  }
}
```

**Lưu ý `s3_key`:** format `{team_id}/{match_id}/original.mp4` — **không** có prefix `raw-videos/` lặp lại tên bucket (quyết định Q18).

**Validation ở backend trước khi cấp URL** (quyết định Q28):
- `content_type` phải thuộc danh sách: `video/mp4`, `video/quicktime`
- `file_size_bytes` không vượt `2147483648` (2 GB)
- Match phải đang ở trạng thái `pending` (không cấp URL cho match đã xử lý xong)

**Rate limiting:** tối đa **10 request/phút/user** trên endpoint này (quyết định Q33, dùng `@nestjs/throttler`).

**Lỗi có thể:** `INVALID_FILE_TYPE` (400), `FILE_TOO_LARGE` (400), `TOO_MANY_REQUESTS` (429)

---

### `POST /v1/matches/{match_id}/confirm-upload`
Client gọi sau khi upload S3 thành công. **Bắt buộc giữ** (quyết định Q27) — đây là trigger chính xác cho transition `pending → uploaded`, do Backend ghi trực tiếp qua `prisma.write` nên phản hồi tức thì cho UI, không phải chờ event bất đồng bộ.

**Response 200:** trả về match object với `processing_status = "uploaded"`.

**Lỗi có thể:** `INVALID_STATE_TRANSITION` (409) nếu match không ở trạng thái `pending`

---

### `GET /v1/matches/{match_id}/status`
Endpoint polling trạng thái xử lý.

**Response 200:**
```json
{
  "success": true,
  "data": {
    "match_id": "uuid",
    "processing_status": "processing",
    "error_message": null,
    "progress_percent": 45
  }
}
```
`processing_status` nhận **5 giá trị** (quyết định Q10): `pending`, `uploaded`, `processing`, `completed`, `failed`

| Giá trị | Ý nghĩa với người dùng |
|---|---|
| `pending` | Đã tạo trận, chưa upload video |
| `uploaded` | Upload xong, đang chờ hệ thống nhận job |
| `processing` | AI đang phân tích video |
| `completed` | Xong, xem được highlight |
| `failed` | Lỗi — `error_message` chứa lý do |

**Ghi chú:** `progress_percent` là optional, chỉ có nếu worker báo tiến độ chi tiết (không bắt buộc ở bản đầu).

---

### `GET /v1/matches/{match_id}/highlights`
Lấy danh sách highlight clip đã xử lý xong (nguồn từ DynamoDB `matchlens-{env}-match-events`).

**Response 200:**
```json
{
  "success": true,
  "data": {
    "match_id": "uuid",
    "highlights": [
      {
        "event_id": "0000000342500-9f2a1c7e4b",
        "event_type": "shot",
        "timestamp_in_video": 342.5,
        "clip_url": "https://cdn.matchlens.com/clips/...?Policy=...&Signature=...&Key-Pair-Id=...",
        "confidence_score": 0.91,
        "track_ids_involved": [1, 7]
      }
    ]
  }
}
```

**`clip_url` là CloudFront Signed URL** (quyết định Q23), hiệu lực **4 giờ**. S3 bucket private hoàn toàn, chỉ CloudFront truy cập qua OAC — bảo vệ video chiến thuật của đội bóng, đồng thời vẫn dùng được CDN cache.

> ⚠️ **BẮT BUỘC:** Backend phải **filter bỏ** item có `event_id` bắt đầu bằng `"MARKER#"` khi query DynamoDB (quyết định D5) — đó là cờ idempotency của Worker, không phải highlight thật. Nếu quên, HLV sẽ thấy 1 clip rỗng không phát được.

**Lỗi có thể:** `PROCESSING_NOT_COMPLETED` (409) nếu gọi khi `processing_status != "completed"`

---

### `GET /v1/matches/{match_id}/stats`
Chỉ số phân tích trong phạm vi trận đấu (nguồn từ Athena/curated-data). **Phase 6.**

**Response 200:**
```json
{
  "success": true,
  "data": {
    "match_id": "uuid",
    "grid_size": { "x": 10, "y": 6 },
    "field_dimensions": { "length_m": 105, "width_m": 68 },
    "player_stats": [
      {
        "track_id": 1,
        "player_id": "uuid-hoac-null",
        "player_name": "Quang Hải",
        "team_side": "home",
        "distance_covered_km": 8.4,
        "avg_speed_kmh": 7.2,
        "max_speed_kmh": 24.1,
        "total_active_time_sec": 5280,
        "heatmap": [
          { "x": 5, "y": 3, "intensity": 85 }
        ]
      }
    ]
  }
}
```

**Điểm quan trọng:**
- **Khóa nhận diện là `track_id`**, không phải `player_id` (quyết định Q25) — v1 không OCR số áo. `player_id`/`player_name` lấy từ JOIN với bảng RDS `match_track_mappings`; `null` nếu HLV chưa gán
- **Không có `heatmap_url` (PNG)** (quyết định Q31) — trả mảng số thô, React render bằng HTML5 Canvas đè lên hình sân. Không có thành phần nào trong hệ thống sinh ảnh
- `heatmap[].x` ∈ [0, 9], `heatmap[].y` ∈ [0, 5] theo lưới **10 × 6** (quyết định Q32)

**Lỗi có thể:** `STATS_NOT_AVAILABLE` (404) nếu Glue ETL Job chưa chạy xong cho trận này

---

### `PUT /v1/matches/{match_id}/track-mappings`
Gán `track_id` → cầu thủ thật (quyết định Q25, D1). **Phase 6.**

**Request:**
```json
{
  "mappings": [
    { "track_id": 1, "player_id": "uuid-cua-quang-hai" },
    { "track_id": 7, "player_id": null }
  ]
}
```
**Response 200:** danh sách mapping sau khi cập nhật.

**Validation:** `player_id` phải thuộc cùng team với match (chống gán cầu thủ của đội khác). `player_id: null` = bỏ gán.

**Lỗi có thể:** `PLAYER_NOT_IN_TEAM` (400), `VALIDATION_ERROR` (400)

---

### `GET /v1/teams/{team_id}/matches`
Danh sách toàn bộ trận đấu của 1 đội (dùng cho trang danh sách chính).

**Response 200:** mảng các match object rút gọn (không bao gồm highlights/stats chi tiết, chỉ metadata cơ bản).

---

### `DELETE /v1/matches/{match_id}`
Xóa trận đấu — cần làm rõ khi thiết kế: có xóa luôn dữ liệu S3/DynamoDB liên quan không, hay chỉ đánh dấu ẩn (soft-delete). Khuyến nghị: chỉ soft-delete ở RDS trước, dọn dữ liệu S3 định kỳ qua job riêng để tránh xóa nhầm dữ liệu đang xử lý dở.

---

## 7. Bảng tổng hợp toàn bộ endpoint

| Method | Endpoint | Mục đích | Auth | Phase |
|---|---|---|---|---|
| GET | /health | Health check cho ALB/ECS | Không | 0 |
| POST | /v1/auth/register | Đăng ký tài khoản | Không | 0 |
| POST | /v1/auth/login | Đăng nhập | Không | 0 |
| POST | /v1/auth/refresh | Làm mới token (kèm rotation) | Không (dùng refresh_token) | 0 |
| POST | /v1/auth/logout | Revoke refresh token | Có | 0 |
| POST | /v1/teams | Tạo đội | Có | 0 |
| GET | /v1/teams | Danh sách đội của user | Có | 0 |
| GET | /v1/teams/{team_id} | Chi tiết 1 đội | Có | 0 |
| POST | /v1/teams/{team_id}/players | Thêm cầu thủ | Có | 0 |
| GET | /v1/teams/{team_id}/players | Danh sách cầu thủ | Có | 0 |
| PUT | /v1/teams/{team_id}/players/{player_id} | Cập nhật cầu thủ | Có | 0 |
| DELETE | /v1/teams/{team_id}/players/{player_id} | Xóa cầu thủ (soft-delete) | Có | 0 |
| POST | /v1/teams/{team_id}/matches | Tạo trận đấu | Có | 0 |
| GET | /v1/teams/{team_id}/matches | Danh sách trận đấu | Có | 0 |
| POST | /v1/matches/{match_id}/upload-url | Lấy presigned URL upload video | Có | 1 |
| POST | /v1/matches/{match_id}/confirm-upload | Xác nhận đã upload xong | Có | 1 |
| GET | /v1/matches/{match_id}/status | Trạng thái xử lý | Có | 1 |
| GET | /v1/matches/{match_id}/highlights | Danh sách highlight | Có | 1 |
| GET | /v1/matches/{match_id}/stats | Chỉ số cầu thủ trong trận | Có | 6 |
| PUT | /v1/matches/{match_id}/track-mappings | Gán track_id → cầu thủ | Có | 6 |
| DELETE | /v1/matches/{match_id} | Xóa trận đấu (soft-delete) | Có | 1 |

---

## 8. Quy tắc phân quyền (Authorization) áp dụng chung

- Mọi thao tác trên `team`, `player`, `match` đều phải kiểm tra resource đó có thuộc về `request.user.id` trong token hay không (qua `owner_id` của team)
- Không cho phép user A truy cập dữ liệu của user B dù biết chính xác `team_id`/`match_id` (chống IDOR)
- Việc kiểm tra đặt thành **guard dùng chung** (`ResourceOwnershipGuard`), không viết lặp lại ở từng endpoint

### 8.1. Guard cho endpoint có `:team_id` trong path
Query `teams` theo `team_id`, so `team.owner_id` với `request.user.id`.

### 8.2. Guard cho endpoint chỉ có `:match_id` (quyết định Q11)

Áp dụng cho: `/matches/{match_id}/upload-url`, `/confirm-upload`, `/status`, `/highlights`, `/stats`, `/track-mappings`, `DELETE /matches/{match_id}`.

1. Đọc `match_id` từ `request.params`
2. Query bằng **`prisma.write` (Master client)** — **không** dùng `prisma.read`
3. Lấy `match.team_id` → `team.owner_id`
4. Cho qua nếu `team.owner_id === request.user.id` **hoặc** `request.user.role === 'admin'`
5. Ngược lại → `403 FORBIDDEN`

> **Lý do bắt buộc dùng Master:** kiểm tra phân quyền đọc từ Read Replica có replication lag sẽ gây `403` oan ngay sau khi user vừa tạo team/match. Đây là **ngoại lệ có chủ đích** của quy tắc "thao tác đọc dùng replica" ở `backend-architecture.md` mục 4.3.

---

## 9. Câu hỏi còn mở — ĐÃ CHỐT TOÀN BỘ

| Câu hỏi | Quyết định | Mã ADR |
|---|---|---|
| `confirm-upload` có cần thiết? | **Bắt buộc giữ** — là trigger cho transition `pending → uploaded`, Backend ghi trực tiếp để UI phản hồi tức thì | Q27 |
| `/stats` query Athena real-time hay cache? | **Cache** — Backend không gọi Athena trực tiếp trong luồng request-response (Athena có độ trễ vài giây). Cơ chế cache cụ thể chốt khi vào Phase 6 | — |
| Có endpoint xóa 1 highlight clip cụ thể? | **Không** ở v1 — nếu AI detect sai, HLV bỏ qua clip đó. Có thể bổ sung sau nếu cần | — |
| Rate-limit `/upload-url` bao nhiêu? | **10 req/phút/user**, áp dụng ở tầng NestJS (`@nestjs/throttler`) | Q33 |

Chi tiết đầy đủ: `docs/decision-record.md`.

---

## 10. Việc cần làm tiếp theo

API Design này đã đồng bộ với `docs/decision-record.md`. Cấu trúc code NestJS tương ứng ở `docs/backend-architecture.md`; schema DB ở `docs/database-schema.md`; ma trận IAM ở `docs/iam-security-design.md`.

