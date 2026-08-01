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
  "s3_key": "raw-videos/660e8400.../550e8400.../original.mp4",
  "uploaded_at": "2026-08-01T10:30:00Z"
}
```

| Field | Kiểu | Bắt buộc | Ghi chú |
|---|---|---|---|
| `match_id` | UUID string | Có | Dùng làm partition key khi ghi DynamoDB/S3 |
| `team_id` | UUID string | Có | Phục vụ tổ chức đường dẫn S3 output theo `{team_id}/{match_id}/` |
| `s3_bucket` | string | Có | Bucket chứa video gốc |
| `s3_key` | string | Có | Đường dẫn chính xác tới file video |
| `uploaded_at` | ISO 8601 string | Có | Thời điểm upload, dùng để log/debug độ trễ pipeline |

---

## 2. DynamoDB Table `MatchEvents` — Schema chi tiết

### 2.1. Key Schema

| Thuộc tính | Vai trò | Kiểu | Ví dụ |
|---|---|---|---|
| `match_id` | **Partition Key** | String (S) | `"550e8400-e29b-41d4-a716-446655440000"` |
| `event_id` | **Sort Key** | String (S) | `"01J5X8K9QZ..."` (ULID — sắp xếp được theo thời gian tạo) |

### 2.2. Toàn bộ Attribute

```json
{
  "match_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_id": "01J5X8K9QZ7X3F2Y8H6N9P4R5T",
  "event_type": "shot",
  "timestamp_in_video": 342.5,
  "highlight_clip_s3_key": "processed-highlights/550e8400.../clips/01J5X8K9QZ.mp4",
  "confidence_score": 0.91,
  "players_involved": ["player_uuid_1", "player_uuid_2"],
  "created_at": "2026-08-01T10:45:23Z"
}
```

| Attribute | Kiểu DynamoDB | Bắt buộc | Ghi chú |
|---|---|---|---|
| `match_id` | S | Có | Partition Key |
| `event_id` | S | Có | Sort Key, dùng ULID (không dùng UUID thuần vì ULID sort được theo thời gian) |
| `event_type` | S | Có | Giá trị cho phép: `"shot"`, `"foul"`, `"fast_break"`, `"goal"`, `"corner_kick"` |
| `timestamp_in_video` | N | Có | Đơn vị giây (số thực, cho phép phần thập phân) |
| `highlight_clip_s3_key` | S | Có | Đường dẫn S3 tới clip đã cắt (trong bucket `processed-highlights`) |
| `confidence_score` | N | Có | Giá trị 0.0 - 1.0, độ tin cậy của model |
| `players_involved` | L (List of S) | Không | Danh sách `player_id` liên quan tới sự kiện, có thể rỗng nếu model chưa nhận diện được cầu thủ cụ thể |
| `created_at` | S | Có | ISO 8601, thời điểm Worker ghi record này |

**Giá trị cho phép của `event_type`** (enum cố định, Worker và Backend phải đồng bộ danh sách này):
```
shot | foul | fast_break | goal | corner_kick
```

### 2.3. Global Secondary Index (tùy chọn, dự phòng)

Nếu sau này cần lọc theo loại sự kiện xuyên suốt nhiều trận:
```
GSI: event_type-index
  Partition Key: event_type
  Sort Key: created_at
```
**Chưa triển khai ở bản đầu** — chỉ ghi chú để dự phòng nếu tính năng lọc theo loại sự kiện được yêu cầu sau này.

---

## 3. S3 — `raw-tracking-data` — JSON Schema chi tiết

Đây là dữ liệu quan trọng nhất cần thống nhất chính xác, vì Glue ETL sẽ đọc trực tiếp theo schema này.

### 3.1. Đường dẫn file

```
raw-tracking-data/{team_id}/{match_id}/tracking_batch_{batch_number}.json
```

**Quyết định:** ghi theo **batch** (gộp nhiều frame vào 1 file), không ghi từng frame riêng lẻ — theo khuyến nghị đã nêu ở `data-model.md` mục 5. Mỗi batch gộp khoảng 100-500 frame/file để cân bằng giữa số lượng S3 object và kích thước file.

### 3.2. Cấu trúc JSON

```json
{
  "match_id": "550e8400-e29b-41d4-a716-446655440000",
  "batch_number": 1,
  "frame_rate": 25,
  "frames": [
    {
      "frame": 1,
      "timestamp_sec": 0.04,
      "detections": [
        {
          "player_id": "770e8400-e29b-41d4-a716-446655440000",
          "jersey_number": 10,
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
| `match_id` | string (UUID) | Có | |
| `batch_number` | integer | Có | Thứ tự batch trong video, tăng dần từ 1 |
| `frame_rate` | integer | Có | FPS của video gốc, cần để tính lại timestamp chính xác nếu cần |
| `frames` | array | Có | Danh sách frame trong batch này |
| `frames[].frame` | integer | Có | Số thứ tự frame trong toàn bộ video |
| `frames[].timestamp_sec` | float | Có | Giây trong video |
| `frames[].detections` | array | Có | Danh sách cầu thủ được detect trong frame này, có thể rỗng |
| `detections[].player_id` | string (UUID) hoặc `null` | Không | `null` nếu model detect được người nhưng chưa map được với cầu thủ cụ thể (chưa nhận diện số áo) |
| `detections[].jersey_number` | integer hoặc `null` | Không | Số áo nhận diện được (nếu có) |
| `detections[].team_side` | string | Có | `"home"` hoặc `"away"` |
| `detections[].bbox` | object | Có | Tọa độ bounding box trên khung hình (pixel), dùng để debug/vẽ lại nếu cần |
| `detections[].position_field` | object | Có | Tọa độ quy đổi sang hệ tọa độ sân bóng chuẩn hóa (0-100 theo chiều dài/rộng sân) — **đây là field quan trọng nhất cho việc tính heatmap** |
| `detections[].confidence` | float | Có | 0.0 - 1.0 |
| `frames[].ball_position` | object hoặc `null` | Không | Tọa độ bóng trong frame, `null` nếu không detect được |

**Quy ước hệ tọa độ sân (`position_field`):** chuẩn hóa về khoảng `x: 0-100`, `y: 0-100`, tương ứng chiều dài và chiều rộng sân bóng (0,0 là góc sân, 100,100 là góc đối diện) — độc lập với độ phân giải video gốc, để mọi trận đấu (dù quay từ góc camera khác nhau) đều dùng chung 1 hệ quy chiếu khi tính heatmap.

---

## 4. S3 — `curated-data` — Schema Parquet (Output của Glue ETL)

### 4.1. File `player_stats.parquet`

```
curated-data/{team_id}/{match_id}/player_stats.parquet
```

| Cột | Kiểu | Ghi chú |
|---|---|---|
| `match_id` | string | |
| `player_id` | string | `null` nếu không map được cầu thủ |
| `jersey_number` | int | |
| `team_side` | string | |
| `distance_covered_km` | float | Tổng quãng đường di chuyển, tính từ chuỗi `position_field` |
| `avg_speed_kmh` | float | Tốc độ trung bình |
| `max_speed_kmh` | float | Tốc độ cao nhất ghi nhận được |
| `total_active_time_sec` | float | Tổng thời gian xuất hiện trên sân (theo detection) |

### 4.2. File `heatmap_data.parquet`

```
curated-data/{team_id}/{match_id}/heatmap_data.parquet
```

| Cột | Kiểu | Ghi chú |
|---|---|---|
| `match_id` | string | |
| `player_id` | string | |
| `position_x_bucket` | int | Tọa độ x đã chia lưới (ví dụ lưới 20x20 để tính mật độ) |
| `position_y_bucket` | int | Tọa độ y đã chia lưới |
| `occurrence_count` | int | Số lần cầu thủ xuất hiện tại ô lưới này — dùng vẽ heatmap |

---

## 5. Trách nhiệm từng phía theo Data Contract này

| Thành phần | Trách nhiệm |
|---|---|
| **AI Worker (Python)** | Đảm bảo ghi đúng 100% theo schema mục 2 (DynamoDB) và mục 3 (S3 JSON). Validate schema trước khi ghi (dùng `pydantic` để định nghĩa model tương ứng, tránh lỗi runtime) |
| **AWS Glue ETL Job** | Đọc đúng theo schema mục 3, xuất ra đúng schema mục 4. Cần xử lý an toàn trường hợp `player_id: null` hoặc `ball_position: null` (không crash job) |
| **Backend NestJS** | Đọc DynamoDB theo schema mục 2 khi trả về `/matches/{id}/highlights`. Danh sách `event_type` hợp lệ (mục 2.2) cần đồng bộ giữa Worker và Backend (dùng chung 1 enum, tránh mỗi bên tự định nghĩa khác nhau) |

---

## 6. Câu hỏi còn mở — cần quyết định trước khi code

- [ ] Có cần versioning cho Data Contract này không (ví dụ field `schema_version` trong mỗi JSON) để sau này có thể thay đổi schema mà không phá vỡ dữ liệu cũ đã lưu?
- [ ] `position_field` (tọa độ sân chuẩn hóa) do chính Worker tự tính toán (cần biết góc quay camera, calibration) hay đây là bài toán để đơn giản hóa ở bản đầu (ví dụ giả định camera cố định, tính theo 1 công thức fix cứng)? — đây là điểm kỹ thuật AI khó, nên ghi chú rõ giới hạn/đơn giản hóa trong `README.md` phần Worker để không bị hỏi quá sâu khi phỏng vấn
- [ ] `jersey_number` detect qua OCR số áo hay chỉ dựa vào phân loại "home/away" đơn giản ở bản đầu? (khuyến nghị bản đầu chỉ cần `team_side`, để `jersey_number`/`player_id` là `null` — bổ sung nhận diện số áo là tính năng nâng cao có thể làm sau)

---

## 7. Việc cần làm tiếp theo

Sau khi có Data Contracts này, kết hợp với `docs/database-schema.md` và `docs/backend-architecture.md`, toàn bộ đặc tả kỹ thuật đã đủ để bắt đầu code cả 3 phần: Backend NestJS, AI Worker Python, và Glue ETL Job.

