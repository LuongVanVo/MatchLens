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

**Read Replica chỉ tồn tại ở `staging`/`prod`** (quyết định Q3): ở `dev`, cả 2 biến `DATABASE_URL_MASTER` và `DATABASE_URL_REPLICA` cùng trỏ về endpoint Master để tiết kiệm ~$14/tháng. Code Backend **không đổi** giữa các môi trường — vẫn luôn có 2 PrismaClient, chỉ khác giá trị biến môi trường. Nhờ vậy quy tắc chọn client được viết đúng ngay từ dev.

**Độ trễ replication:** Read Replica dùng async replication, có độ trễ nhỏ (thường dưới 1 giây nhưng không đảm bảo tuyệt đối) — Backend cần lưu ý không đọc từ Replica ngay sau khi vừa ghi vào Master nếu cần dữ liệu real-time tuyệt đối (ví dụ ngay sau khi tạo match mới, nên đọc lại từ Master hoặc trả thẳng dữ liệu vừa tạo từ response, không query lại Replica).

**Ngoại lệ bắt buộc dùng Master:** `ResourceOwnershipGuard` (kiểm tra phân quyền chống IDOR) **luôn** query qua Master, không qua Replica — vì replication lag sẽ gây `403 FORBIDDEN` oan ngay sau khi user vừa tạo team/match (quyết định Q11).

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
| status | VARCHAR(50) / enum | `pending`, `uploaded`, `processing`, `completed`, `failed` — **5 giá trị** |
| error_message | TEXT | Lý do nếu `status = 'failed'` |
| duration_sec | INTEGER | Độ dài video, ghi sau khi worker xử lý xong |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

**Ghi chú thiết kế:**
- Cột tên chính xác trong DB là **`status`** (API DTO dùng key `processing_status` — quyết định Q10), với **5 giá trị**: `pending`, `uploaded`, `processing`, `completed`, `failed`
- Đây là **nguồn chân lý (source of truth)** cho trạng thái xử lý mà endpoint `GET /matches/{id}/status` trả về
- **Chỉ 2 thành phần được ghi cột này** (quyết định Q20): Backend API Service (ghi `pending`, `uploaded`) và Lambda `status-updater-fn` (ghi `processing`, `completed`, `failed`). AI Worker và Job Dispatcher **không có RDS credential** — chúng gửi message vào SQS `match-status-callbacks`, Lambda này là thành phần duy nhất đọc queue đó và ghi RDS
- Không lưu danh sách highlight clip trực tiếp trong RDS — dữ liệu này nằm ở DynamoDB (mục 2) vì đặc tính truy vấn khác nhau (xem lý do ở mục 2.1)
- State machine đầy đủ + quy tắc validate transition: `docs/database-schema.md` mục 3

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

### 2.2. Bảng `matchlens-{env}-match-events`

| Thuộc tính | Vai trò | Kiểu dữ liệu | Ghi chú |
|---|---|---|---|
| `match_id` | Partition Key | String (UUID) | Từ RDS matches.id |
| `event_id` | Sort Key | String **tất định** (`{ts_ms:013d}-{hash10}`) | **Không dùng ULID random** — xem lý do ở `data-contracts.md` mục 2.2 (quyết định Q22) |
| `event_type` | Attribute | String | `shot`, `foul`, `fast_break`, `goal`, `corner_kick` |
| `timestamp_in_video` | Attribute | Number | Giây trong video xảy ra sự kiện |
| `highlight_clip_s3_key` | Attribute | String | Đường dẫn tới **bản transcode** (`clips/...`) |
| `confidence_score` | Attribute | Number | Độ tin cậy của model khi detect |
| `track_ids_involved` | Attribute | List of Number | `track_id` liên quan (thay cho `players_involved` vì v1 không map được player — quyết định Q25) |
| `created_at` | Attribute | String (ISO 8601) | |

**Item đặc biệt `MARKER#COMPLETED`** (quyết định Q22, D5): mỗi match có thêm 1 item với `event_id = "MARKER#COMPLETED"` làm cờ idempotency, **chỉ có** `match_id` + `event_id` + `created_at`. Backend `GET /highlights` **bắt buộc filter bỏ** mọi item có `event_id` bắt đầu bằng `"MARKER#"` — nếu quên, HLV sẽ thấy 1 highlight rỗng không phát được.

Schema đầy đủ và chính xác: `docs/data-contracts.md` mục 2.

### 2.3. Access pattern dự kiến
- Lấy toàn bộ highlight của 1 trận: `Query` theo `match_id` — rất nhanh, đúng sở trường DynamoDB
- Lấy highlight theo loại sự kiện cụ thể (vd chỉ xem các pha `shot`): cân nhắc thêm **Global Secondary Index (GSI)** với partition key `event_type` nếu tính năng lọc theo loại sự kiện được yêu cầu

---

## 3. S3 — Object Storage (video, dữ liệu tracking, dữ liệu phân tích)

### 3.1. Nguyên tắc tổ chức bucket
Tách bucket theo **giai đoạn xử lý dữ liệu** (raw → processed → curated) thay vì gộp chung 1 bucket — giúp áp dụng lifecycle policy và IAM permission riêng biệt cho từng giai đoạn, đúng chuẩn data lake.

**Tổng số bucket: 5** (4 bucket data lake + 1 bucket kết quả Athena, quyết định Q30).

### 3.2. Chi tiết từng bucket

> **Quyết định Q18, Q19:** object key **không** lặp lại prefix trùng tên bucket, và **bắt buộc** có `{team_id}` ở mọi bucket để IAM policy condition theo prefix dùng được đồng đều (nền tảng multi-tenancy).

#### `matchlens-{env}-raw-videos`
```
{team_id}/{match_id}/original.mp4
```
- Nơi user upload video gốc qua presigned URL
- Lifecycle: chuyển sang S3 Glacier sau 30 ngày, xóa sau 90 ngày (video gốc không cần giữ vĩnh viễn sau khi đã xử lý xong)

#### `matchlens-{env}-processed-highlights`
```
raw-clips/{team_id}/{match_id}/{event_id}.mp4     ← Worker ghi (INPUT của MediaConvert)
clips/{team_id}/{match_id}/{event_id}.mp4         ← MediaConvert ghi (OUTPUT, client xem)
```
- **Tách 2 prefix gốc là yêu cầu bắt buộc** (quyết định Q19b): S3 Event Notification cấu hình `filter_prefix = "raw-clips/"`. Vì MediaConvert ghi output vào `clips/` — không khớp filter — nên không thể tự kích hoạt lại chính nó, tránh **vòng lặp đệ quy vô hạn** tốn chi phí thật.
- `highlight_clip_s3_key` trong DynamoDB lưu đường dẫn bản transcode (`clips/...`), hợp lệ vì key tất định — Worker biết trước MediaConvert sẽ ghi ra đâu.
- **Bucket private hoàn toàn** (quyết định Q23): chỉ CloudFront truy cập qua OAC, client nhận CloudFront Signed URL hiệu lực 4 giờ.
- Lifecycle: xóa prefix `raw-clips/` sau 7 ngày (không cần giữ bản thô sau khi đã transcode); prefix `clips/` giữ lâu dài, cân nhắc S3 Intelligent-Tiering.

#### `matchlens-{env}-raw-tracking-data`
```
{team_id}/{match_id}/tracking_batch_{batch_number}.json
```
- Dữ liệu tọa độ thô theo **batch** (100-500 frame/file, không ghi từng frame riêng lẻ) — input cho Analytics Pipeline (Glue ETL)
- Schema chính xác: `docs/data-contracts.md` mục 3
- Lifecycle: chuyển sang Glacier sau khi Glue đã xử lý xong

#### `matchlens-{env}-curated-data`
```
team_id={team_id}/match_id={match_id}/player_stats.parquet
team_id={team_id}/match_id={match_id}/heatmap_data.parquet
```
- **Hive-style partitioning** (`key=value/`) là yêu cầu bắt buộc (quyết định Q19): Glue Crawler tự nhận `team_id` và `match_id` thành **partition column**, nhờ đó Athena query `WHERE team_id = '...'` chỉ scan đúng partition thay vì toàn bộ bucket — giảm cả độ trễ lẫn chi phí (Athena tính tiền theo dung lượng scan).
- Output của Glue ETL Job, định dạng Parquet — dữ liệu "gold layer", giữ lâu dài

#### `matchlens-{env}-athena-results`
```
{query_execution_id}/...     ← Athena tự sinh cấu trúc
```
- Nơi Athena ghi kết quả query (bắt buộc phải có, quyết định Q30)
- Lifecycle: **xóa vĩnh viễn sau 7 ngày** — kết quả query là dữ liệu tạm, không có giá trị lưu trữ

### 3.3. Naming convention chung
- Prefix theo `{team_id}/{match_id}/...` ở mọi bucket giúp áp dụng IAM Policy Condition giới hạn quyền truy cập theo prefix (nền tảng cho multi-tenancy chặt chẽ hơn sau này)
- Riêng `curated-data` dùng cú pháp Hive `team_id={team_id}/match_id={match_id}/` để Glue Crawler nhận thành partition column
- Tên bucket theo format `matchlens-{env}-{purpose}` (xem đầy đủ ở `docs/naming-tagging-standard.md` mục 2.2)

---

## 4. Tổng hợp lựa chọn lưu trữ theo loại dữ liệu

| Loại dữ liệu | Nơi lưu | Lý do |
|---|---|---|
| User, team, player, match metadata | RDS PostgreSQL | Có quan hệ rõ ràng, cần JOIN, giao dịch (transaction) cần ACID |
| Refresh token (revocation) | RDS PostgreSQL (`refresh_tokens`) | Cần revoke được khi logout, quan hệ với user — quyết định Q12 |
| Mapping `track_id → player_id` | RDS PostgreSQL (`match_track_mappings`) | HLV gán thủ công, cần JOIN với players để hiển thị tên thật — quyết định D1/Q25 |
| Sự kiện highlight (event detection) | DynamoDB | Ghi nhanh, khối lượng lớn, truy vấn đơn giản theo match_id |
| Video gốc, video đã xử lý | S3 | Dữ liệu dạng file lớn, không phù hợp lưu trong database |
| Dữ liệu tracking thô (tọa độ từng frame) | S3 (raw-tracking-data) | Khối lượng cực lớn, chỉ cần đọc theo batch cho ETL, không cần truy vấn ngẫu nhiên |
| Dữ liệu chỉ số đã tính toán (player stats) | S3 (curated-data, Parquet) | Tối ưu cho truy vấn phân tích qua Athena, không cần OLTP |
| Kết quả query Athena (tạm) | S3 (athena-results) | Athena bắt buộc cần S3 location; lifecycle xóa sau 7 ngày |

---

## 5. Câu hỏi còn mở — ĐÃ CHỐT

| Câu hỏi | Quyết định | Mã ADR |
|---|---|---|
| Có cần bảng `match_events` tóm tắt trong RDS song song với DynamoDB? | **Không** — chỉ dùng DynamoDB. Nếu sau này cần báo cáo tổng hợp nhiều trận, dùng Athena trên curated-data thay vì nhân bản dữ liệu vào RDS | — |
| Tracking thô gộp batch hay ghi từng frame? | **Gộp batch** 100-500 frame/file | Q19 |
| Có soft-delete (`deleted_at`) cho bảng RDS? | **Có** — mọi bảng chính đều có `deleted_at` (xem `database-schema.md`) | — |
| Multi-tenancy: 1 user nhiều team? | **Chưa** ở v1 — chỉ `owner_id` trên teams. Bảng trung gian `team_members` để dành cho mở rộng sau | — |

Chi tiết đầy đủ: `docs/decision-record.md`.

---

## 6. Việc cần làm tiếp theo

Data Model này đã được đồng bộ với `docs/decision-record.md`. Đặc tả chi tiết cột/ràng buộc từng bảng RDS ở `docs/database-schema.md`; schema chính xác của DynamoDB item, JSON tracking và Parquet ở `docs/data-contracts.md`.

