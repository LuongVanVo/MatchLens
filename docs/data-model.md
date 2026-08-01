# MatchLens — Data Model Design

> Thiết kế chi tiết toàn bộ dữ liệu của hệ thống: schema RDS (PostgreSQL), cấu trúc DynamoDB, tổ chức S3 Bucket, và các quyết định thiết kế đi kèm lý do.

---

## 1. RDS PostgreSQL — Dữ liệu quan hệ (metadata nghiệp vụ)

### 1.1. Lý do dùng RDS cho nhóm dữ liệu này
Dữ liệu users, teams, matches, players có quan hệ chặt chẽ với nhau (1 team có nhiều player, 1 match thuộc 1 team, cần JOIN thường xuyên khi hiển thị) — phù hợp với database quan hệ hơn NoSQL.

### 1.1.1. Cấu trúc RDS: Master + Standby (Multi-AZ) + Read Replica

| Instance | Vai trò | Nhận traffic |
|---|---|---|
| **Master** | Ghi + đọc chính | Toàn bộ thao tác ghi (tạo/sửa/xóa team, player, match) và đọc mặc định từ Backend API |
| **Standby** (Multi-AZ) | Dự phòng, tự động failover | Không nhận traffic trực tiếp — chỉ kích hoạt khi Master gặp sự cố |
| **Read Replica** | Chỉ đọc, async replication từ Master | Truy vấn đọc tải lớn: danh sách trận đấu/đội/cầu thủ khi nhiều user truy cập đồng thời, phục vụ các trang có lượng đọc cao (dashboard danh sách, trang chủ team) |

**Lý do bổ sung Read Replica:** tách traffic đọc (đặc biệt các trang liệt kê, dashboard) khỏi Master để không ảnh hưởng hiệu năng ghi (upload video, tạo trận đấu) khi có nhiều user cùng truy cập xem dữ liệu.

**Lưu ý quan trọng — Read Replica KHÔNG phục vụ phân tích chỉ số cầu thủ:** dữ liệu heatmap, quãng đường di chuyển, tốc độ (Performance Analytics) không nằm trong RDS — dữ liệu này đi qua pipeline riêng (S3 curated-data → Athena → QuickSight, xem mục 4). Read Replica chỉ phục vụ đọc metadata nghiệp vụ (team, player, match) với tải lớn, không phải nơi Backend query cho tính năng visualize chỉ số.

**Độ trễ replication:** Read Replica dùng async replication, có độ trễ nhỏ (thường dưới 1 giây nhưng không đảm bảo tuyệt đối) — Backend cần lưu ý không đọc từ Replica ngay sau khi vừa ghi vào Master nếu cần dữ liệu real-time tuyệt đối (ví dụ ngay sau khi tạo match mới, nên đọc lại từ Master hoặc trả thẳng dữ liệu vừa tạo từ response, không query lại Replica).

### 1.2. ERD tổng quan

```
users ──1:N── teams (owner_id)
teams ──1:N── players
teams ──1:N── matches
matches ──1:N── match_events (tùy chọn, nếu cần lưu event tóm tắt ở RDS)
```

### 1.3. Chi tiết từng bảng

#### `users`
| Cột | Kiểu dữ liệu | Ghi chú |
|---|---|---|
| id | UUID (PK) | |
| email | VARCHAR(255) UNIQUE | Dùng để đăng nhập |
| password_hash | VARCHAR(255) | Hash bằng bcrypt/argon2, không lưu plaintext |
| full_name | VARCHAR(255) | |
| role | VARCHAR(50) | `coach`, `admin` — phục vụ phân quyền cơ bản |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

#### `teams`
| Cột | Kiểu dữ liệu | Ghi chú |
|---|---|---|
| id | UUID (PK) | |
| owner_id | UUID (FK → users.id) | HLV sở hữu đội |
| name | VARCHAR(255) | Tên đội |
| created_at | TIMESTAMP | |

#### `players`
| Cột | Kiểu dữ liệu | Ghi chú |
|---|---|---|
| id | UUID (PK) | |
| team_id | UUID (FK → teams.id) | |
| full_name | VARCHAR(255) | |
| jersey_number | INT | Số áo — dùng để map với detection nếu sau này nhận diện số áo |
| position | VARCHAR(50) | Vị trí thi đấu (tiền đạo, hậu vệ...) |
| created_at | TIMESTAMP | |

#### `matches`
| Cột | Kiểu dữ liệu | Ghi chú |
|---|---|---|
| id | UUID (PK) | |
| team_id | UUID (FK → teams.id) | |
| opponent_name | VARCHAR(255) | Tên đối thủ (dạng text tự do, không cần bảng riêng) |
| match_date | DATE | |
| video_s3_key | VARCHAR(512) | Đường dẫn S3 tới video gốc (raw-videos) |
| processing_status | VARCHAR(50) | `pending`, `processing`, `completed`, `failed` |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

**Ghi chú thiết kế:**
- `processing_status` ở đây là **nguồn chân lý (source of truth)** cho trạng thái xử lý mà endpoint `GET /matches/{id}/status` sẽ trả về — được Backend cập nhật khi nhận callback/polling từ pipeline xử lý (worker cập nhật trực tiếp qua DB, hoặc qua một Lambda riêng lắng nghe kết quả)
- Không lưu danh sách highlight clip trực tiếp trong RDS — dữ liệu này nằm ở DynamoDB (mục 2) vì đặc tính truy vấn khác nhau (xem lý do ở mục 2.1)

### 1.4. Index cần thiết
- `users.email` — unique index, phục vụ login
- `teams.owner_id` — phục vụ truy vấn "danh sách đội của 1 HLV"
- `matches.team_id` — phục vụ truy vấn "danh sách trận đấu của 1 đội"
- `players.team_id` — phục vụ truy vấn "danh sách cầu thủ của 1 đội"

---

## 2. DynamoDB — Detection Metadata (dữ liệu sự kiện tốc độ cao)

### 2.1. Lý do dùng DynamoDB thay vì RDS cho dữ liệu này
- Dữ liệu sự kiện (mỗi lần detect 1 pha bóng đáng chú ý) có khối lượng ghi lớn, tần suất cao trong thời gian ngắn (worker xử lý 1 video sinh ra hàng chục/hàng trăm event cùng lúc) — phù hợp với mô hình ghi nhanh (high write throughput) của DynamoDB hơn RDS
- Truy vấn chính chỉ cần theo `match_id` (lấy toàn bộ highlight của 1 trận) — access pattern đơn giản, không cần JOIN phức tạp, rất hợp với NoSQL key-value

### 2.2. Bảng `MatchEvents`

| Thuộc tính | Vai trò | Kiểu dữ liệu | Ghi chú |
|---|---|---|---|
| `match_id` | Partition Key | String (UUID) | Từ RDS matches.id |
| `event_id` | Sort Key | String (ULID/timestamp-based) | Đảm bảo sắp xếp theo thời gian phát sinh |
| `event_type` | Attribute | String | `shot`, `foul`, `fast_break`, `goal`... |
| `timestamp_in_video` | Attribute | Number | Giây trong video xảy ra sự kiện |
| `highlight_clip_s3_key` | Attribute | String | Đường dẫn S3 tới clip đã cắt (processed-highlights) |
| `confidence_score` | Attribute | Number | Độ tin cậy của model khi detect (phục vụ lọc sau này) |
| `created_at` | Attribute | String (ISO 8601) | |

### 2.3. Access pattern dự kiến
- Lấy toàn bộ highlight của 1 trận: `Query` theo `match_id` — rất nhanh, đúng sở trường DynamoDB
- Lấy highlight theo loại sự kiện cụ thể (vd chỉ xem các pha `shot`): cân nhắc thêm **Global Secondary Index (GSI)** với partition key `event_type` nếu tính năng lọc theo loại sự kiện được yêu cầu

---

## 3. S3 — Object Storage (video, dữ liệu tracking, dữ liệu phân tích)

### 3.1. Nguyên tắc tổ chức bucket
Tách bucket theo **giai đoạn xử lý dữ liệu** (raw → processed → curated) thay vì gộp chung 1 bucket — giúp áp dụng lifecycle policy và IAM permission riêng biệt cho từng giai đoạn, đúng chuẩn data lake.

### 3.2. Chi tiết từng bucket

#### `matchlens-{env}-raw-videos`
```
raw-videos/{team_id}/{match_id}/original.mp4
```
- Nơi user upload video gốc qua presigned URL
- Lifecycle: chuyển sang S3 Glacier sau 30 ngày, xóa sau 90 ngày (video gốc không cần giữ vĩnh viễn sau khi đã xử lý xong)

#### `matchlens-{env}-processed-highlights`
```
processed-highlights/{match_id}/clips/{event_id}.mp4
processed-highlights/{match_id}/clips/{event_id}_transcoded.mp4
```
- Clip do Worker cắt ra, và bản đã qua MediaConvert transcode
- Lifecycle: giữ lâu dài (đây là sản phẩm chính người dùng xem lại), có thể cân nhắc S3 Intelligent-Tiering để tự tối ưu chi phí theo tần suất truy cập

#### `matchlens-{env}-raw-tracking-data`
```
raw-tracking-data/{match_id}/frames/{frame_number}.json
```
hoặc gộp theo batch để giảm số lượng object nhỏ:
```
raw-tracking-data/{match_id}/tracking_batch_{batch_id}.json
```
- Dữ liệu tọa độ thô từng frame — input cho Analytics Pipeline (Glue ETL)
- Lifecycle: có thể chuyển sang Glacier sau khi Glue đã xử lý xong (vì dữ liệu curated đã đủ dùng cho phân tích về sau)

#### `matchlens-{env}-curated-data`
```
curated-data/{match_id}/player_stats.parquet
curated-data/{match_id}/heatmap_data.parquet
```
- Output của Glue ETL Job, định dạng Parquet tối ưu cho Athena query
- Đây là dữ liệu "gold layer" — giữ lâu dài, dung lượng nhỏ hơn nhiều so với raw

### 3.3. Naming convention chung
- Prefix theo `{team_id}/{match_id}/...` giúp dễ áp dụng IAM Policy Condition (giới hạn quyền truy cập theo prefix nếu sau này cần multi-tenancy chặt chẽ hơn)
- Tên bucket theo format `matchlens-{env}-{purpose}` (đồng bộ với naming convention chung của toàn hệ thống)

---

## 4. Tổng hợp lựa chọn lưu trữ theo loại dữ liệu

| Loại dữ liệu | Nơi lưu | Lý do |
|---|---|---|
| User, team, player, match metadata | RDS PostgreSQL | Có quan hệ rõ ràng, cần JOIN, giao dịch (transaction) cần ACID |
| Sự kiện highlight (event detection) | DynamoDB | Ghi nhanh, khối lượng lớn, truy vấn đơn giản theo match_id |
| Video gốc, video đã xử lý | S3 | Dữ liệu dạng file lớn, không phù hợp lưu trong database |
| Dữ liệu tracking thô (tọa độ từng frame) | S3 (raw-tracking-data) | Khối lượng cực lớn, chỉ cần đọc theo batch cho ETL, không cần truy vấn ngẫu nhiên |
| Dữ liệu chỉ số đã tính toán (player stats) | S3 (curated-data, Parquet) | Tối ưu cho truy vấn phân tích qua Athena, không cần OLTP |

---

## 5. Câu hỏi còn mở — cần quyết định trước khi code

- [ ] Có cần bảng `match_events` tóm tắt trong RDS (song song với DynamoDB) để phục vụ báo cáo tổng hợp nhanh không, hay chỉ dùng DynamoDB là đủ?
- [ ] Dữ liệu tracking thô nên gộp theo batch (giảm số lượng S3 object nhỏ, giảm chi phí PUT request) hay ghi theo từng frame riêng lẻ (đơn giản hơn khi code Worker)? — khuyến nghị **gộp theo batch**
- [ ] Có cần soft-delete (cột `deleted_at`) cho các bảng RDS thay vì xóa cứng không, để tránh mất dữ liệu do thao tác nhầm?
- [ ] Multi-tenancy: hiện tại thiết kế cho phép 1 user thuộc nhiều team hay chỉ sở hữu team qua `owner_id`? Nếu cần nhiều HLV cùng quản lý 1 đội, cần thêm bảng trung gian `team_members`

---

## 6. Việc cần làm tiếp theo

Sau khi chốt Data Model này, bước tiếp theo trong giai đoạn thiết kế là **API Design** (`docs/api-spec.md`) — vì cấu trúc endpoint và request/response schema sẽ dựa trực tiếp vào các bảng/thuộc tính đã định nghĩa ở đây.

