# MatchLens — API Design

> Thiết kế chi tiết toàn bộ API của hệ thống, dựa trên Data Model (`docs/data-model.md`) và System Flows (`docs/system-flows.md`) đã chốt. Phạm vi hiện tại: tính năng lõi theo từng trận đấu (upload, highlight, phân tích chỉ số trong 1 trận). Chưa bao gồm endpoint tổng hợp nhiều trận/mùa giải — sẽ bổ sung ở giai đoạn mở rộng sau.

---

## 1. Nguyên tắc thiết kế chung

- REST API, version hóa ngay từ đầu: tất cả endpoint có prefix `/v1/`
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
- Auth: JWT Bearer Token, gửi qua header `Authorization: Bearer {token}`
- Toàn bộ endpoint (trừ `/auth/*`) yêu cầu token hợp lệ
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
- `access_token`: JWT, thời hạn ngắn (ví dụ 15-30 phút), dùng cho mọi request
- `refresh_token`: thời hạn dài hơn (ví dụ 7 ngày), lưu ở httpOnly cookie hoặc client storage an toàn, dùng để lấy access_token mới mà không cần đăng nhập lại
- Payload JWT tối thiểu: `{ user_id, email, role, exp }`

### 2.3. Middleware xác thực
Mọi endpoint (trừ auth) đi qua middleware kiểm tra:
1. Token có tồn tại trong header không
2. Token còn hạn, chữ ký hợp lệ không
3. Gắn `user_id` vào context của request để dùng ở các bước xử lý tiếp theo (kiểm tra quyền sở hữu resource)

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

**Lỗi có thể:** `INVALID_REFRESH_TOKEN` (401)

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
    "upload_url": "https://matchlens-dev-raw-videos.s3.amazonaws.com/...",
    "s3_key": "raw-videos/{team_id}/{match_id}/original.mp4",
    "expires_in": 900
  }
}
```
**Validation ở backend trước khi cấp URL:**
- `content_type` phải thuộc danh sách cho phép (`video/mp4`, `video/quicktime`...)
- `file_size_bytes` không vượt giới hạn cấu hình (ví dụ tối đa 2GB)

**Lỗi có thể:** `INVALID_FILE_TYPE` (400), `FILE_TOO_LARGE` (400)

---

### `POST /v1/matches/{match_id}/confirm-upload`
Client gọi sau khi upload S3 thành công, để backend cập nhật `processing_status = "pending"` → thực tế bước này có thể không bắt buộc nếu dùng S3 Event Notification làm nguồn kích hoạt chính (theo System Flows), nhưng nên có để backend chủ động cập nhật UI ngay, không cần chờ event bất đồng bộ.

**Response 200:** trả về match object với `processing_status` cập nhật.

---

### `GET /v1/matches/{match_id}/status`
Endpoint polling trạng thái xử lý (theo đúng System Flows mục 3).

**Response 200:**
```json
{
  "success": true,
  "data": {
    "match_id": "uuid",
    "processing_status": "processing",
    "progress_percent": 45
  }
}
```
`processing_status` nhận giá trị: `pending`, `processing`, `completed`, `failed`

**Ghi chú:** `progress_percent` là optional, chỉ có nếu worker có báo cáo tiến độ chi tiết (không bắt buộc ở bản đầu tiên).

---

### `GET /v1/matches/{match_id}/highlights`
Lấy danh sách highlight clip đã xử lý xong (dữ liệu nguồn từ DynamoDB `MatchEvents`).

**Response 200:**
```json
{
  "success": true,
  "data": {
    "match_id": "uuid",
    "highlights": [
      {
        "event_id": "ulid-string",
        "event_type": "shot",
        "timestamp_in_video": 342,
        "clip_url": "https://cdn.matchlens.com/processed-highlights/...",
        "confidence_score": 0.91
      }
    ]
  }
}
```
**Lỗi có thể:** `PROCESSING_NOT_COMPLETED` (409) nếu gọi khi `processing_status != "completed"`

---

### `GET /v1/matches/{match_id}/stats`
Lấy chỉ số phân tích cầu thủ trong phạm vi trận đấu này (dữ liệu nguồn từ Athena/curated-data, backend query hộ hoặc cache lại kết quả).

**Response 200:**
```json
{
  "success": true,
  "data": {
    "match_id": "uuid",
    "player_stats": [
      {
        "player_id": "uuid",
        "distance_covered_km": 8.4,
        "avg_speed_kmh": 7.2,
        "heatmap_url": "https://cdn.matchlens.com/curated-data/.../heatmap.png"
      }
    ]
  }
}
```
**Lỗi có thể:** `STATS_NOT_AVAILABLE` (404) nếu Glue ETL Job chưa chạy xong cho trận này

---

### `GET /v1/teams/{team_id}/matches`
Danh sách toàn bộ trận đấu của 1 đội (dùng cho trang danh sách chính).

**Response 200:** mảng các match object rút gọn (không bao gồm highlights/stats chi tiết, chỉ metadata cơ bản).

---

### `DELETE /v1/matches/{match_id}`
Xóa trận đấu — cần làm rõ khi thiết kế: có xóa luôn dữ liệu S3/DynamoDB liên quan không, hay chỉ đánh dấu ẩn (soft-delete). Khuyến nghị: chỉ soft-delete ở RDS trước, dọn dữ liệu S3 định kỳ qua job riêng để tránh xóa nhầm dữ liệu đang xử lý dở.

---

## 7. Bảng tổng hợp toàn bộ endpoint

| Method | Endpoint | Mục đích | Auth |
|---|---|---|---|
| POST | /v1/auth/register | Đăng ký tài khoản | Không |
| POST | /v1/auth/login | Đăng nhập | Không |
| POST | /v1/auth/refresh | Làm mới token | Không (dùng refresh_token) |
| POST | /v1/teams | Tạo đội | Có |
| GET | /v1/teams | Danh sách đội của user | Có |
| GET | /v1/teams/{team_id} | Chi tiết 1 đội | Có |
| POST | /v1/teams/{team_id}/players | Thêm cầu thủ | Có |
| GET | /v1/teams/{team_id}/players | Danh sách cầu thủ | Có |
| PUT | /v1/teams/{team_id}/players/{player_id} | Cập nhật cầu thủ | Có |
| DELETE | /v1/teams/{team_id}/players/{player_id} | Xóa cầu thủ | Có |
| POST | /v1/teams/{team_id}/matches | Tạo trận đấu | Có |
| GET | /v1/teams/{team_id}/matches | Danh sách trận đấu | Có |
| POST | /v1/matches/{match_id}/upload-url | Lấy presigned URL upload video | Có |
| POST | /v1/matches/{match_id}/confirm-upload | Xác nhận đã upload xong | Có |
| GET | /v1/matches/{match_id}/status | Trạng thái xử lý | Có |
| GET | /v1/matches/{match_id}/highlights | Danh sách highlight | Có |
| GET | /v1/matches/{match_id}/stats | Chỉ số cầu thủ trong trận | Có |
| DELETE | /v1/matches/{match_id} | Xóa trận đấu | Có |

---

## 8. Quy tắc phân quyền (Authorization) áp dụng chung

- Mọi thao tác trên `team`, `player`, `match` đều phải kiểm tra resource đó có thuộc về `user_id` trong token hay không (qua `owner_id` của team)
- Không cho phép user A truy cập dữ liệu của user B dù biết chính xác `team_id`/`match_id` (tránh lỗi IDOR — Insecure Direct Object Reference)
- Việc kiểm tra này nên đặt thành middleware/dependency dùng chung, không viết lặp lại ở từng endpoint

---

## 9. Câu hỏi còn mở — cần quyết định trước khi code

- [ ] `confirm-upload` có thực sự cần thiết không, hay để hoàn toàn dựa vào S3 Event Notification để tránh phải đồng bộ 2 nguồn cập nhật trạng thái?
- [ ] Endpoint `/stats` nên để backend real-time query Athena (chậm hơn, luôn mới nhất) hay cache kết quả vào RDS/DynamoDB sau khi Glue Job chạy xong (nhanh hơn, cần thêm bước đồng bộ)? — khuyến nghị cache lại để tránh gọi Athena trực tiếp từ request người dùng (Athena có độ trễ vài giây, không phù hợp gọi trong luồng request-response thông thường)
- [ ] Có cần endpoint riêng để hủy/xóa 1 highlight clip cụ thể (nếu AI detect sai) không?
- [ ] Rate-limiting cho endpoint `/upload-url` để tránh bị lạm dụng tạo nhiều presigned URL — nên áp dụng ở API Gateway hoặc Lambda, cần quyết định giới hạn cụ thể (ví dụ tối đa X lần/phút/user)

---

## 10. Việc cần làm tiếp theo

Sau khi chốt API Design, bước tiếp theo trong giai đoạn thiết kế là **IAM & Security Design** (`docs/iam-matrix.md`) — vì giờ đã biết rõ backend cần thao tác với những resource nào (S3 bucket nào, DynamoDB table nào, RDS nào) để xây ma trận quyền least-privilege chính xác cho từng service.

