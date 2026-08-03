# MatchLens — Data Contracts (AI Worker ↔ Data Pipeline)

> Đặc tả chính xác định dạng dữ liệu trao đổi giữa AI Worker (Python), DynamoDB, S3, và AWS Glue ETL. Đây là "hợp đồng" bắt buộc cả 2 phía (Worker ghi ra, Glue đọc vào) phải tuân thủ tuyệt đối — thay đổi schema ở đây bắt buộc phải đồng bộ cả code Worker lẫn Glue ETL Job.

---

## 1. SQS Message Schema (Lambda Dispatcher → SQS → AI Worker)

Đây là input đầu tiên Worker nhận được, cần thống nhất trước cả DynamoDB/S3 output.

```json
{
  "match_id": "550e8400-e29b-41d4-a716-446655440000",
  "team_id": "660e8400-e29b-41d4-a716-446655440000",
  "s3_bucket": "matchlens-dev-raw-videos",
  "s3_key": "660e8400-e29b-41d4-a716-446655440000/550e8400-e29b-41d4-a716-446655440000/original.mp4",
  "uploaded_at": "2026-08-01T10:30:00Z"
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|---|---|---|---|
| `match_id` | UUID string | Có | Dùng làm partition key khi ghi DynamoDB/S3 |
| `team_id` | UUID string | Có | Phục vụ tổ chức đường dẫn S3 output theo `{team_id}/{match_id}/` |
| `s3_bucket` | string | Có | Bucket chứa video gốc |
| `s3_key` | string | Có | Đường dẫn chính xác tới file video — format `{team_id}/{match_id}/original.mp4`, **không** có prefix `raw-videos/` (quyết định Q18) |
| `uploaded_at` | ISO 8601 string | Có | Thời điểm upload, dùng để log/debug độ trễ pipeline |

---

## 1.1. SQS Message Schema — `match-status-callbacks` (Worker/Dispatcher → Lambda status-updater)

> Queue mới theo quyết định Q20. Worker và Job Dispatcher **không có RDS credential** — mọi thay đổi `matches.status` sau bước `uploaded` đều đi qua queue này.

```json
{
  "match_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "reason": null,
  "duration_sec": 5400,
  "emitted_at": "2026-08-01T10:45:23Z"
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|---|---|---|---|
| `match_id` | UUID string | Có | Match cần cập nhật trạng thái |
| `status` | string | Có | Chỉ nhận `"processing"`, `"completed"`, `"failed"` — Lambda **từ chối** `pending`/`uploaded` (2 giá trị đó do Backend ghi trực tiếp) |
| `reason` | string hoặc `null` | Không | **Bắt buộc có giá trị khi `status = "failed"`** → Lambda ghi vào `matches.error_message` |
| `duration_sec` | integer hoặc `null` | Không | Worker báo độ dài video khi `status = "completed"` → ghi vào `matches.duration_sec` |
| `emitted_at` | ISO 8601 string | Có | Thời điểm phát sinh message, dùng debug độ trễ |

**Trách nhiệm Lambda `status-updater-fn`:** validate transition hợp lệ trước khi UPDATE (xem `database-schema.md` mục 3) — nếu message yêu cầu transition không hợp lệ (ví dụ `completed → processing`), Lambda ghi log cảnh báo và **bỏ qua** message (không throw, tránh message quay vòng vô ích vào DLQ).

---

## 2. DynamoDB Table `matchlens-{env}-match-events` — Schema chi tiết

### 2.1. Key Schema

| Thuộc tính | Vai trò | Kiểu | Ví dụ |
|---|---|---|---|
| `match_id` | **Partition Key** | String (S) | `"550e8400-e29b-41d4-a716-446655440000"` |
| `event_id` | **Sort Key** | String (S) | `"0000000342500-9f2a1c7e4b"` (tất định — xem mục 2.4) |

### 2.2. Toàn bộ Attribute

```json
{
  "match_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_id": "0000000342500-9f2a1c7e4b",
  "event_type": "shot",
  "timestamp_in_video": 342.5,
  "highlight_clip_s3_key": "clips/660e8400.../550e8400.../0000000342500-9f2a1c7e4b.mp4",
  "confidence_score": 0.91,
  "track_ids_involved": [1, 7],
  "created_at": "2026-08-01T10:45:23Z"
}
```

| Attribute | Kiểu DynamoDB | Bắt buộc | Ghi chú |
|---|---|---|---|
| `match_id` | S | Có | Partition Key |
| `event_id` | S | Có | Sort Key, **tất định** (không dùng ULID random — xem mục 2.4) |
| `event_type` | S | Có | Giá trị cho phép: `"shot"`, `"foul"`, `"fast_break"`, `"goal"`, `"corner_kick"` |
| `timestamp_in_video` | N | Có | Đơn vị giây (số thực, cho phép phần thập phân) |
| `highlight_clip_s3_key` | S | Có | Đường dẫn tới **bản transcode**: `clips/{team_id}/{match_id}/{event_id}.mp4`. Worker ghi trước khi MediaConvert xong — hợp lệ vì key tất định, và Backend chỉ trả `/highlights` khi `status = 'completed'` (quyết định Q19b) |
| `confidence_score` | N | Có | Giá trị 0.0 - 1.0, độ tin cậy của model |
| `track_ids_involved` | L (List of N) | Không | Danh sách `track_id` liên quan tới sự kiện. **Thay cho `players_involved`** vì v1 không map được `player_id` (quyết định Q25). Có thể rỗng |
| `created_at` | S | Có | ISO 8601, thời điểm Worker ghi record này |

**Giá trị cho phép của `event_type`** (enum cố định, Worker và Backend phải dùng chung 1 định nghĩa):
```
shot | foul | fast_break | goal | corner_kick
```

### 2.3. Item đặc biệt `MARKER#COMPLETED` — ngoại lệ được đặc tả của contract

Ngoài các item sự kiện, mỗi match có thêm **1 item cờ idempotency**:

```json
{
  "match_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_id": "MARKER#COMPLETED",
  "created_at": "2026-08-01T10:50:00Z"
}
```

Item này **cố tình thiếu** các attribute vốn là bắt buộc ở mục 2.2 (`event_type`, `timestamp_in_video`, `highlight_clip_s3_key`, `confidence_score`). Đây là ngoại lệ hợp lệ, không phải lỗi dữ liệu.

> ⚠️ **BẮT BUỘC:** Backend `GET /matches/{id}/highlights` **phải filter bỏ** mọi item có `event_id` bắt đầu bằng `"MARKER#"`. Nếu quên, HLV sẽ thấy 1 highlight rỗng không phát được. Mọi consumer khác của bảng này (Glue ETL, script phân tích) cũng phải áp dụng filter tương tự.

### 2.4. `event_id` tất định — cơ chế idempotency (quyết định Q22)

**Không dùng ULID random.** `event_id` được dẫn xuất từ nội dung sự kiện:

```python
import hashlib

def make_event_id(match_id: str, timestamp_in_video: float, event_type: str) -> str:
    ts_ms  = int(timestamp_in_video * 1000)
    payload = f"{match_id}|{timestamp_in_video}|{event_type}"
    hash10 = hashlib.sha256(payload.encode()).hexdigest()[:10]
    return f"{ts_ms:013d}-{hash10}"      # ví dụ: "0000000342500-9f2a1c7e4b"
```

**Lý do bắt buộc phải tất định:** với ULID random, mỗi lần SQS redeliver sẽ sinh khóa hoàn toàn mới → `PutItem` **không** overwrite → nếu Worker crash giữa đường (đã ghi 3/50 event, chưa kịp ghi marker), lần chạy lại tạo thêm 50 item → tổng 53 → HLV thấy 3 highlight lặp. Khóa tất định đảm bảo cùng sự kiện → cùng khóa → `PutItem` overwrite thật sự, nên **retry an toàn ở mọi thời điểm crash**.

**Vẫn sort được theo thời gian** (yêu cầu gốc của Sort Key): 13 chữ số đầu là timestamp millisecond zero-padded, nên sort lexicographic tương đương sort theo thời gian. Phần hash 10 ký tự chỉ để chống trùng khi 2 sự kiện khác loại xảy ra cùng millisecond.

### 2.5. Luồng idempotency đầy đủ của Worker

```
1. Nhận SQS message  →  GetItem(match_id, "MARKER#COMPLETED")
2. Nếu TỒN TẠI       →  DeleteMessage khỏi SQS, kết thúc (job đã xong trước đó)
3. Nếu KHÔNG tồn tại →  chạy YOLOv11 inference
4.                      PutItem từng event (event_id tất định → overwrite an toàn)
5.                      Ghi batch JSON tracking lên S3
6.                      Ghi clip lên S3 prefix raw-clips/
7.                      PutItem MARKER#COMPLETED     ← BƯỚC CUỐI CÙNG
8.                      SendMessage {status:"completed"} vào match-status-callbacks
9.                      DeleteMessage khỏi SQS
```

Marker phải ghi ở **bước 7, sau khi mọi dữ liệu đã ghi xong** — nếu ghi sớm hơn, crash sau đó sẽ khiến job bị coi là hoàn thành trong khi dữ liệu còn thiếu.

### 2.6. Global Secondary Index (tùy chọn, dự phòng)

Nếu sau này cần lọc theo loại sự kiện xuyên suốt nhiều trận:
```
GSI: event_type-index
  Partition Key: event_type
  Sort Key: created_at
```
**Chưa triển khai ở bản đầu** — chỉ ghi chú để dự phòng.

---

## 3. S3 — `raw-tracking-data` — JSON Schema chi tiết

Đây là dữ liệu quan trọng nhất cần thống nhất chính xác, vì Glue ETL sẽ đọc trực tiếp theo schema này.

### 3.1. Đường dẫn file

```
{team_id}/{match_id}/tracking_batch_{batch_number}.json
```

**Quyết định Q18, Q19:** không có prefix trùng tên bucket; **bắt buộc** có `{team_id}` để IAM policy condition theo prefix dùng được.

**Quyết định:** ghi theo **batch** (gộp nhiều frame vào 1 file), không ghi từng frame riêng lẻ. Mỗi batch gộp khoảng 100-500 frame/file để cân bằng giữa số lượng S3 object và kích thước file.

### 3.2. Cấu trúc JSON

```json
{
  "schema_version": 1,
  "match_id": "550e8400-e29b-41d4-a716-446655440000",
  "batch_number": 1,
  "frame_rate": 25,
  "field_dimensions": { "length_m": 105, "width_m": 68 },
  "frames": [
    {
      "frame": 1,
      "timestamp_sec": 0.04,
      "detections": [
        {
          "track_id": 1,
          "player_id": null,
          "jersey_number": null,
          "team_side": "home",
          "bbox": { "x": 452.3, "y": 301.8, "width": 34.2, "height": 78.5 },
          "position_field": { "x": 45.2, "y": 30.5 },
          "confidence": 0.94
        }
      ],
      "ball_position": { "x": 448.1, "y": 305.2, "confidence": 0.88 }
    }
  ]
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|---|---|---|---|
| `schema_version` | integer | **Có** | Hiện tại `1`. Glue ETL **fail-fast với message rõ ràng** nếu gặp version chưa hỗ trợ (quyết định Q26) |
| `match_id` | string (UUID) | Có | |
| `batch_number` | integer | Có | Thứ tự batch trong video, tăng dần từ 1 |
| `frame_rate` | integer | Có | FPS của video gốc, cần để tính lại timestamp và tốc độ |
| `field_dimensions` | object | **Có** | `{length_m, width_m}` — kích thước sân thật, để ETL quy đổi `position_field` sang mét (quyết định Q24) |
| `frames` | array | Có | Danh sách frame trong batch này |
| `frames[].frame` | integer | Có | Số thứ tự frame trong toàn bộ video |
| `frames[].timestamp_sec` | float | Có | Giây trong video |
| `frames[].detections` | array | Có | Danh sách đối tượng detect được trong frame, có thể rỗng |
| `detections[].track_id` | integer | **Có** | ID bền vững do tracker (ByteTrack/BoT-SORT) sinh, duy nhất trong 1 trận. **Đây là khóa nhận diện cầu thủ ở v1** (quyết định Q25) |
| `detections[].player_id` | string (UUID) hoặc `null` | Không | **Luôn `null` ở v1** — giữ field cho tương lai khi có OCR số áo |
| `detections[].jersey_number` | integer hoặc `null` | Không | **Luôn `null` ở v1** |
| `detections[].team_side` | string | Có | `"home"` hoặc `"away"` |
| `detections[].bbox` | object | Có | Tọa độ bounding box trên khung hình, đơn vị **pixel** — chỉ dùng debug/vẽ overlay |
| `detections[].position_field` | object | Có | Tọa độ sân **chuẩn hóa 0-100** — **field quan trọng nhất cho heatmap và mọi chỉ số vận động** |
| `detections[].confidence` | float | Có | 0.0 - 1.0 |
| `frames[].ball_position` | object hoặc `null` | Không | Tọa độ bóng (pixel), `null` nếu không detect được |

**⚠️ Hai hệ tọa độ khác nhau trong cùng 1 detection — không được lẫn:**

| Field | Hệ tọa độ | Đơn vị | Dùng cho |
|---|---|---|---|
| `bbox` | Khung hình video | pixel, phụ thuộc độ phân giải | Chỉ debug / vẽ lại overlay |
| `position_field` | Sân bóng chuẩn hóa | 0-100, độc lập độ phân giải & góc camera | **Mọi tính toán trong Glue ETL** |

Glue ETL **tuyệt đối không** tính quãng đường/tốc độ từ `bbox`.

### 3.3. Quy ước hệ tọa độ `position_field` (quyết định Q24)

Chuẩn hóa về `x: 0-100` (chiều dài sân), `y: 0-100` (chiều rộng sân); `(0,0)` là một góc sân, `(100,100)` là góc đối diện. Độc lập với độ phân giải video và góc camera, để mọi trận đấu dùng chung 1 hệ quy chiếu.

**Cách ETL quy đổi sang mét** — dùng `field_dimensions` đọc từ chính file, **không** hardcode hằng số:

```python
x_m = detection["position_field"]["x"] * (field_dimensions["length_m"] / 100)
y_m = detection["position_field"]["y"] * (field_dimensions["width_m"]  / 100)
```

**Lý do có `field_dimensions`:** sân bóng phong trào thường không đúng chuẩn 105×68m. Ghi kèm kích thước thật vào chính file dữ liệu khiến JSON **tự mô tả (self-describing)** — ETL không phải giả định, và dữ liệu cũ vẫn tính đúng nếu sau này xử lý sân kích thước khác.

### 3.4. Cách Worker tính `position_field` ở v1 — Fixed Static Tactical Camera

**Giả định đơn giản hóa đã chốt** (quyết định Q24):
- Camera **tĩnh**, góc quay **cố định** suốt trận (camera chiến thuật đặt trên khán đài)
- Cấu hình trước **4 điểm mốc sân** (field anchor points) đã biết tọa độ cho mỗi video — ví dụ 4 góc sân, hoặc 4 góc vòng cấm
- Dùng OpenCV tính ma trận homography rồi project tọa độ pixel → tọa độ sân:

```python
import cv2, numpy as np

# src: 4 điểm trong ảnh (pixel) — cấu hình thủ công cho mỗi video
# dst: 4 điểm tương ứng trên sân (mét)
H, _ = cv2.findHomography(src_points, dst_points)

# Lấy điểm giữa đáy bbox làm vị trí chân cầu thủ trên mặt sân
foot = np.array([[[bbox_x + bbox_width / 2, bbox_y + bbox_height]]], dtype=np.float32)
pitch_m = cv2.perspectiveTransform(foot, H)[0][0]     # (x_m, y_m)

# Chuẩn hóa về 0-100 trước khi ghi JSON
position_field = {
    "x": round(pitch_m[0] / field_length_m * 100, 2),
    "y": round(pitch_m[1] / field_width_m  * 100, 2),
}
```

**Giới hạn phải ghi rõ trong `README.md`:** phương pháp này không hoạt động với camera di chuyển/zoom (broadcast footage). Đây là đơn giản hóa có chủ ý ở v1; xử lý camera động cần camera calibration động — nằm ngoài phạm vi dự án.

---

## 4. S3 — `curated-data` — Schema Parquet (Output của Glue ETL)

> **Hive-style partitioning bắt buộc** (quyết định Q19): Glue Crawler tự nhận `team_id`/`match_id` thành partition column, Athena query `WHERE team_id = '...'` chỉ scan đúng partition.
>
> **Khóa nhận diện là `track_id`, không phải `player_id`** (quyết định Q25) — v1 không map được cầu thủ, việc gán do HLV làm thủ công qua bảng RDS `match_track_mappings`.

### 4.1. File `player_stats.parquet`

```
team_id={team_id}/match_id={match_id}/player_stats.parquet
```

| Cột | Kiểu | Ghi chú |
|---|---|---|
| `track_id` | int | **Khóa chính về mặt logic** — ID do tracker sinh |
| `team_side` | string | `"home"` / `"away"` |
| `distance_covered_km` | float | Tổng quãng đường, tính từ chuỗi `position_field` đã quy đổi sang mét |
| `avg_speed_kmh` | float | Tốc độ trung bình |
| `max_speed_kmh` | float | Tốc độ cao nhất ghi nhận được |
| `total_active_time_sec` | float | Tổng thời gian xuất hiện trên sân (theo detection) |

**Lưu ý:** `match_id` và `team_id` **không** là cột trong file — chúng là partition column, Glue/Athena tự suy ra từ đường dẫn. Ghi lặp lại trong file là dư thừa và tăng dung lượng.

Cột `player_id` và `jersey_number` **đã loại bỏ** khỏi Parquet — thông tin này nằm ở RDS (`match_track_mappings`), Backend JOIN khi trả về `/stats`.

### 4.2. File `heatmap_data.parquet`

```
team_id={team_id}/match_id={match_id}/heatmap_data.parquet
```

| Cột | Kiểu | Ghi chú |
|---|---|---|
| `track_id` | int | |
| `position_x_bucket` | int | Ô lưới theo chiều dài sân, giá trị **0-9** |
| `position_y_bucket` | int | Ô lưới theo chiều rộng sân, giá trị **0-5** |
| `occurrence_count` | int | Số frame cầu thủ xuất hiện tại ô lưới này |

**Kích thước lưới chốt: 10 × 6 = 60 vùng chiến thuật** (quyết định Q32) — mỗi ô ~10.5m × 11.3m trên sân 105×68m, tương ứng vùng chiến thuật có ý nghĩa với HLV.

**Công thức chia lưới trong ETL** (từ `position_field` chuẩn hóa 0-100):

```python
x_bucket = min(int(position_field["x"] / 10),        9)   # 100 / 10 buckets
y_bucket = min(int(position_field["y"] / (100 / 6)), 5)   # 100 /  6 buckets
```

`min()` là **bắt buộc** để chặn edge case tọa độ đúng bằng 100 tràn ra ngoài mảng (`int(100/10) = 10` → vượt index 9).

**Không có file PNG heatmap** (quyết định Q31): Backend trả mảng số thô, React render bằng HTML5 Canvas. Không có thành phần nào trong hệ thống sinh ảnh.

---

## 5. Trách nhiệm từng phía theo Data Contract này

| Thành phần | Trách nhiệm |
|---|---|
| **AI Worker (Python)** | Ghi đúng 100% schema mục 2 (DynamoDB) và mục 3 (S3 JSON). Validate bằng `pydantic` trước khi ghi. Sinh `event_id` **tất định** theo mục 2.4. Ghi `MARKER#COMPLETED` ở bước cuối. Gửi callback status vào SQS theo mục 1.1. **Không** gọi MediaConvert, **không** kết nối RDS |
| **Lambda `status-updater-fn`** | Đọc queue `match-status-callbacks` theo schema mục 1.1, validate transition, UPDATE `matches.status`/`error_message`/`duration_sec`. Thành phần compute duy nhất ngoài Backend có RDS credential |
| **Lambda `mediaconvert-trigger-fn`** | Nhận S3 Event từ prefix `raw-clips/`, tạo MediaConvert job ghi output sang prefix `clips/`. **Không** ghi DynamoDB/RDS |
| **AWS Glue ETL Job** | Đọc schema mục 3, xuất schema mục 4. Kiểm tra `schema_version` (fail-fast nếu lạ). Quy đổi tọa độ bằng `field_dimensions` đọc từ file, **không** hardcode 105/68. Xử lý an toàn `player_id: null`, `jersey_number: null`, `ball_position: null` (không crash). Nhóm theo `track_id` |
| **Backend NestJS** | Đọc DynamoDB theo schema mục 2, **filter bỏ item `MARKER#*`** (mục 2.3). Ghi `matches.status` cho 2 transition đầu (`pending`, `uploaded`). Dùng chung enum `event_type` với Worker. JOIN `match_track_mappings` khi trả `/stats` để hiện tên cầu thủ thật |

---

## 6. Câu hỏi còn mở — ĐÃ CHỐT TOÀN BỘ

| Câu hỏi | Quyết định | Mã ADR |
|---|---|---|
| Có `schema_version` trong JSON? | **Có** — `"schema_version": 1` ở root mọi file tracking | Q26 |
| `position_field` do Worker tự tính thế nào? | **Fixed Static Tactical Camera** — 4 anchor point + OpenCV homography, giữ hệ chuẩn hóa 0-100, kèm `field_dimensions` để ETL quy đổi. Giới hạn ghi rõ ở `README.md` | Q24 |
| Có OCR số áo ở v1? | **Không** — dùng `track_id` từ ByteTrack/BoT-SORT; HLV gán `track_id → player_id` thủ công qua RDS `match_track_mappings` ở Phase 6 | Q25, D1 |
| `event_id` dùng ULID random? | **Không** — dùng khóa tất định `{ts_ms:013d}-{hash10}` để `PutItem` overwrite được khi retry | Q22 |
| Lưới heatmap bao nhiêu ô? | **10 × 6** | Q32 |

Chi tiết đầy đủ: `docs/decision-record.md`.

---

## 7. Việc cần làm tiếp theo

Data Contract này đã đồng bộ hoàn toàn với `docs/decision-record.md`. Trước khi code `worker/` (Phase 1) và `etl/player_stats_job.py` (Phase 6), đọc lại mục 2.4-2.5 (idempotency) và mục 3.3-3.4 (hệ tọa độ) — đây là 2 điểm dễ implement sai nhất.

