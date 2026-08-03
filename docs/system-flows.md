# MatchLens — System Flows

> Mô tả toàn bộ luồng hoạt động của hệ thống, dựa trên sơ đồ kiến trúc đã chốt (`docs/architecture.png`). Bao gồm luồng chính (happy path), luồng lỗi/ngoại lệ, và các luồng vận hành (CI/CD, giám sát, bảo mật).

---

## 1. Luồng xác thực người dùng (Authentication Flow)

1. HLV (Coach/User) truy cập ứng dụng qua trình duyệt → DNS resolve qua **Route 53**
2. Request đi qua **CloudFront**, được **WAF** kiểm tra trước khi cho qua
3. CloudFront route request tới **Origin 1 (ALB)** vì đây là traffic ứng dụng, không phải video
4. ALB phân phối traffic tới **ECS Fargate – Backend API Service** ở 1 trong 2 AZ (theo cơ chế load balancing)
5. Backend xác thực thông tin đăng nhập, kiểm tra với dữ liệu user trong **RDS PostgreSQL**
6. Backend trả về JWT token (hoặc session) cho client
7. Các request tiếp theo từ client đính kèm token này để xác thực

**Trường hợp lỗi:**
- Sai thông tin đăng nhập → Backend trả lỗi 401, không truy vấn thêm
- Token hết hạn → Client cần luồng refresh token hoặc yêu cầu đăng nhập lại

---

## 2. Luồng upload video trận đấu (Video Upload Flow)

1. HLV đã đăng nhập, tạo mới một trận đấu (match) qua Backend API — ghi vào **RDS** với `status = 'pending'`
2. HLV chọn video để upload → Frontend gọi `POST /v1/matches/{match_id}/upload-url`
3. Request đi qua CloudFront → ALB → **Backend API Service**
4. Backend **không nhận file trực tiếp** — validate `content_type` (`video/mp4`, `video/quicktime`) và `file_size_bytes` (≤ 2GB), rate-limit 10 req/phút/user, rồi tạo **presigned URL** (TTL 900s) trỏ tới **S3 `raw-videos`** với key `{team_id}/{match_id}/original.mp4`
5. Client dùng presigned URL để **upload file thẳng lên S3**, không đi qua Backend hay ALB
6. Client gọi `POST /v1/matches/{match_id}/confirm-upload` → Backend ghi `status = 'uploaded'` qua `prisma.write` (đồng bộ, UI phản hồi tức thì — quyết định Q27)
7. Song song, S3 sinh **S3 Event Notification** kích hoạt luồng xử lý AI (mục 3)

**Lý do thiết kế:** tránh để Backend phải xử lý file video dung lượng lớn, giảm tải cho ECS service và chi phí truyền dữ liệu qua ALB.

**Vì sao giữ `confirm-upload` dù đã có S3 Event:** `confirm-upload` cho UI biết ngay lập tức là upload đã xong (không phải chờ event bất đồng bộ), và là transition duy nhất Backend ghi trực tiếp trong luồng này. S3 Event chịu trách nhiệm phần sau (`uploaded → processing`).

**Trường hợp lỗi:**
- Presigned URL hết hạn trước khi upload xong → client gọi lại API để lấy URL mới
- File không đúng định dạng/vượt kích thước → đã bị chặn ở bước 4 trước khi cấp URL
- Client upload xong nhưng không gọi `confirm-upload` (mất mạng, đóng tab) → S3 Event vẫn kích hoạt pipeline, `status-updater-fn` sẽ ghi `processing`. Transition `uploaded → processing` không hợp lệ từ `pending` → Lambda ghi log cảnh báo và bỏ qua. **Cần xử lý:** cho phép `pending → processing` như transition dự phòng, hoặc Backend có job đối soát. Chốt ở Phase 1 khi code Lambda.

---

## 3. Luồng xử lý AI bất đồng bộ — Highlight Engine (Core Async Flow)

Đây là luồng quan trọng nhất của hệ thống, xử lý hoàn toàn bất đồng bộ để không block người dùng.

1. **S3 Event Notification** (từ bước upload, prefix `{team_id}/{match_id}/`) kích hoạt **Lambda Job Dispatcher**
2. Lambda xác thực metadata cơ bản của video, đẩy message vào **SQS `video-processing-jobs`** (schema: `data-contracts.md` mục 1), và gửi callback `{status: "processing"}` vào **SQS `match-status-callbacks`**
3. **ECS Fargate – AI Worker Service** (autoscale theo độ dài queue, về 0 khi rỗng) poll và consume job
4. **Kiểm tra idempotency trước khi xử lý** (quyết định Q22): `GetItem(match_id, "MARKER#COMPLETED")` trên DynamoDB
   - Nếu **tồn tại** → job đã hoàn thành trước đó (SQS redeliver) → xóa message, kết thúc, **không xử lý lại**
   - Nếu **không tồn tại** → tiếp tục bước 5
5. Worker tải video từ S3, chạy inference **YOLOv11 + tracker (ByteTrack/BoT-SORT)** để phát hiện cầu thủ, bóng, sự kiện, và sinh `track_id` bền vững cho từng cầu thủ
6. Worker ghi dữ liệu ra 3 nơi:
   - **S3 `processed-highlights`, prefix `raw-clips/{team_id}/{match_id}/{event_id}.mp4`**: clip thô đã cắt
   - **DynamoDB `match-events`**: 1 item/sự kiện, `event_id` **tất định** (không phải ULID random) nên retry overwrite an toàn
   - **S3 `raw-tracking-data`**: batch JSON 100-500 frame/file (schema: `data-contracts.md` mục 3)
7. Worker ghi **`MARKER#COMPLETED`** vào DynamoDB — **bước cuối cùng**, sau khi mọi dữ liệu đã ghi xong
8. Worker gửi callback `{status: "completed", duration_sec}` vào **SQS `match-status-callbacks`**, rồi xóa message khỏi `video-processing-jobs`
9. **Song song:** S3 Event trên prefix `raw-clips/` kích hoạt **Lambda `mediaconvert-trigger-fn`** → tạo MediaConvert job → transcode → ghi output sang prefix **`clips/{team_id}/{match_id}/{event_id}.mp4`** (quyết định Q21)
10. **Lambda `status-updater-fn`** đọc `match-status-callbacks`, validate transition, UPDATE `matches.status` trong RDS
11. HLV gọi `GET /matches/{id}/status` thấy `completed` → gọi `GET /matches/{id}/highlights` → Backend Query DynamoDB (**filter bỏ item `MARKER#*`**) → sinh **CloudFront Signed URL** hiệu lực 4 giờ cho từng clip
12. Client phát video qua **CloudFront Origin 2** → S3 `processed-highlights` (private, chỉ CloudFront truy cập qua OAC)

**Chống vòng lặp đệ quy S3 → MediaConvert → S3** (quyết định Q19b): S3 Event Notification trên bucket `processed-highlights` cấu hình `filter_prefix = "raw-clips/"`. MediaConvert ghi output vào prefix `clips/` — không khớp filter — nên **không thể tự kích hoạt lại chính nó**. Nếu 2 prefix này gộp làm một, Lambda sẽ trigger vô hạn và tốn chi phí thật.

**Trạng thái xử lý (polling):** `GET /matches/{id}/status` trả 1 trong **5 giá trị**: `pending` → `uploaded` → `processing` → `completed` / `failed`.

### 3.1. Luồng cập nhật `matches.status` — Event-Driven Callback (quyết định Q20)

AI Worker và Job Dispatcher **không có RDS credential** (giữ least-privilege, tránh RDS connection exhaustion khi Worker scale nhiều task). Mọi thay đổi trạng thái sau `uploaded` đi qua đường riêng:

```
Backend NestJS ────prisma.write────────────────────────────> RDS   (pending, uploaded)

Job Dispatcher ─┐
                ├─> SQS match-status-callbacks ─> λ status-updater ─> RDS   (processing,
AI Worker ──────┘              │                                            completed, failed)
                               └─> DLQ ─> CloudWatch Alarm ─> SNS
```

| Transition | Ai ghi | Cơ chế |
|---|---|---|
| `→ pending` | Backend | `prisma.write` trực tiếp |
| `pending → uploaded` | Backend | `prisma.write` trực tiếp (khi client gọi `confirm-upload`) |
| `uploaded → processing` | `status-updater-fn` | Dispatcher gửi callback |
| `processing → completed` | `status-updater-fn` | Worker gửi callback |
| `processing → failed` | `status-updater-fn` | Worker gửi callback / redrive DLQ |

**DLQ cho queue callback là bắt buộc** (quyết định D2): nếu `status-updater-fn` chết (RDS unreachable, bug validate transition), status sẽ **treo ở `processing` vĩnh viễn** — user thấy spinner quay mãi mà không ai biết. Đây là silent failure nguy hiểm hơn cả job AI thất bại, nên phải có Alarm riêng.

**Trường hợp lỗi:**
- Worker xử lý job thất bại (video lỗi, timeout, hết bộ nhớ) → SQS retry theo `visibility_timeout = 900s`
- Sau `max_receive_count = 3` lần → message chuyển vào **DLQ `video-processing-dlq`**
- DLQ có message → **CloudWatch Alarm** → **SNS** → Email/Slack để đội vận hành kiểm tra thủ công
- Worker crash giữa đường (đã ghi 3/50 event) → lần retry **overwrite đúng** những event cũ nhờ `event_id` tất định, không tạo highlight trùng (quyết định Q22)

---

## 4. Luồng phân tích chỉ số cầu thủ — Analytics Pipeline (Data Flow)

Luồng này chạy tách biệt, thường theo lịch (batch) chứ không real-time như highlight.

1. Dữ liệu tracking thô đã có tại **S3 `raw-tracking-data`** (`{team_id}/{match_id}/tracking_batch_*.json`, ghi ra từ bước 6 của luồng Highlight Engine)
2. **AWS Glue ETL Job** chạy theo lịch (hoặc trigger thủ công), đọc dữ liệu raw:
   - Kiểm tra `schema_version` — fail-fast nếu gặp version chưa hỗ trợ
   - Làm sạch dữ liệu (loại bỏ frame lỗi, `position_field` null)
   - Quy đổi `position_field` (0-100) sang mét bằng `field_dimensions` **đọc từ chính file**, không hardcode 105/68
   - Tính chỉ số theo từng **`track_id`** (không phải `player_id` — v1 không OCR số áo): quãng đường (Euclid giữa 2 tọa độ liên tiếp), tốc độ (khoảng cách / delta thời gian theo FPS), heatmap (gom nhóm theo lưới **10×6**)
3. Kết quả ghi vào **S3 `curated-data`** dạng Parquet, **Hive-style partition** `team_id={team_id}/match_id={match_id}/`
4. **Glue Crawler** cập nhật Data Catalog — tự nhận `team_id`/`match_id` thành **partition column**
5. **Amazon Athena** truy vấn SQL trên curated data, ghi kết quả vào **S3 `athena-results`** (lifecycle xóa sau 7 ngày)
6. HLV mở trang thống kê → Frontend hiển thị "Player Track #1 (Home)" + dropdown → HLV gán `track_id → player_id` → Backend lưu vào RDS `match_track_mappings`
7. `GET /matches/{id}/stats` JOIN `match_track_mappings` để trả về tên cầu thủ thật + mảng số heatmap; **React render heatmap bằng HTML5 Canvas** (không có PNG server-side)

**Vì sao Hive partition quan trọng:** Athena tính tiền theo **dung lượng scan**. Không có partition, mỗi query phải scan toàn bộ bucket; có partition, `WHERE team_id = '...'` chỉ đọc đúng thư mục cần — giảm cả độ trễ lẫn chi phí.

**Trường hợp lỗi:**
- Glue Job thất bại (schema thay đổi, thiếu field) → alarm riêng trên Glue Job status, không dùng chung DLQ như SQS
- Gặp `schema_version` lạ → Job fail-fast với message rõ ràng thay vì crash giữa đường khó debug
- Dữ liệu curated không khớp Crawler → Athena query lỗi/thiếu cột, cần review lại schema

---

## 5. Luồng CI/CD (Deployment Flow)

1. Developer push code lên **GitHub**, mở Pull Request
2. **GitHub Actions** được trigger:
   - Build: build Docker image cho Backend API Service và AI Worker Service
   - Scan: quét lỗ hổng bảo mật image bằng **Trivy** — nếu phát hiện lỗ hổng mức nghiêm trọng, pipeline dừng lại
   - Push: đẩy image đã qua kiểm tra lên **Amazon ECR**
3. Deploy theo môi trường:
   - Push vào nhánh feature/dev → tự động deploy lên môi trường **dev**
   - Merge vào nhánh main → tự động deploy lên **staging**
   - Deploy lên **production** yêu cầu **approval thủ công** trước khi ECS service được cập nhật
4. **ECS Services (Backend & AI Worker)** được cập nhật với image mới, thực hiện rolling update để tránh downtime

**Trường hợp lỗi:**
- Build/test thất bại → pipeline dừng ngay, không tới bước deploy
- Deploy lỗi ở production → cần chiến lược rollback (revert về image version trước đó qua ECS task definition trước đó)

---

## 6. Luồng giám sát & cảnh báo (Observability Flow)

1. Toàn bộ service (ECS, RDS, SQS, Lambda, ALB) đẩy metric và log về **CloudWatch**
2. **CloudWatch Dashboard** hiển thị trạng thái tổng quan: CPU/Memory ECS, độ dài SQS queue, tỷ lệ lỗi 5xx từ ALB, dung lượng RDS còn lại
3. **CloudWatch Alarm** được cấu hình cho các ngưỡng quan trọng, ví dụ:
   - SQS DLQ có message mới
   - ECS worker service fail liên tục (health check thất bại)
   - RDS storage vượt ngưỡng cảnh báo
   - Tỷ lệ lỗi 5xx từ ALB vượt ngưỡng
4. Khi alarm kích hoạt → gửi tới **SNS Topic**
5. SNS phân phối thông báo tới **Email/Slack** cho đội vận hành
6. Đội vận hành tra cứu chi tiết qua **CloudWatch Log Insights** để xác định nguyên nhân, tham chiếu runbook tương ứng

---

## 7. Luồng bảo mật & governance (Cross-cutting, không phải luồng tuyến tính)

Đây không phải một luồng chạy tuần tự mà là các cơ chế áp dụng liên tục trên toàn hệ thống:

- **IAM**: mọi service (Backend, Worker, Lambda, Glue) chỉ có quyền truy cập đúng resource cần thiết (least-privilege), không dùng quyền rộng
- **Secrets Manager**: Backend và Worker lấy DB password, API key tại thời điểm khởi động/runtime, không hardcode trong code hay image
- **Security Hub**: liên tục quét toàn bộ tài khoản AWS, tổng hợp finding từ Config, GuardDuty, Inspector
- **AWS Config**: theo dõi thay đổi cấu hình resource, đối chiếu với rule đã định nghĩa (ví dụ: SG không được mở 0.0.0.0/0 vào port 22)
- **GuardDuty**: phát hiện hành vi bất thường (truy cập lạ, IAM key bị lộ có dấu hiệu sử dụng sai mục đích)

Khi có finding mới từ Security Hub → có thể thiết lập luồng tương tự Observability (EventBridge → SNS) để cảnh báo, hoặc mở rộng thành auto-remediation bằng Lambda nếu muốn nâng cấp sau này.

---

## 8. Luồng khôi phục sự cố — Disaster Recovery (kích hoạt khi có sự cố nghiêm trọng)

1. **RDS PostgreSQL (Multi-AZ)** tự động failover sang Standby nếu Primary gặp sự cố — không cần can thiệp thủ công, thời gian gián đoạn ngắn
2. Nếu cần khôi phục từ backup (ví dụ dữ liệu bị lỗi do thao tác sai, không phải do hạ tầng chết):
   - Xác định snapshot gần nhất còn hợp lệ
   - Thực hiện restore snapshot ra RDS instance mới
   - Trỏ lại kết nối Backend API sang instance mới (qua thay đổi endpoint hoặc DNS nội bộ)
   - Đo thời gian thực hiện toàn bộ quá trình → đây chính là **RTO (Recovery Time Objective)** thực tế, ghi lại trong DR Plan
3. Với S3 (raw-videos, processed-highlights, raw-tracking-data): áp dụng versioning nếu cần khôi phục file bị ghi đè/xóa nhầm

---

## 9. Tổng hợp bảng các luồng theo tính chất

| Luồng | Đồng bộ/Bất đồng bộ | Kích hoạt bởi |
|---|---|---|
| Authentication | Đồng bộ | User request |
| Video Upload | Đồng bộ (tạo URL) + trực tiếp client-to-S3 | User action |
| Highlight Engine (AI Processing) | Bất đồng bộ | S3 Event Notification |
| Analytics Pipeline | Bất đồng bộ, theo lịch (batch) | Schedule hoặc trigger thủ công |
| CI/CD | Bất đồng bộ, theo sự kiện Git | Push/Merge code |
| Observability | Liên tục (real-time streaming metric/log) | Hệ thống tự sinh |
| Security & Governance | Liên tục, nền | Hệ thống tự quét |
| Disaster Recovery | Kích hoạt khi có sự cố | Sự cố hạ tầng/dữ liệu |

---

## 10. Ghi chú

- Toàn bộ luồng bất đồng bộ (Highlight Engine, Analytics) đều cần có cơ chế theo dõi trạng thái (status tracking) để người dùng không bị "treo" chờ không rõ tiến độ
- Các luồng lỗi (DLQ, Glue Job fail, RDS failover) nên được diễn tập thử (chaos testing ở mức đơn giản) trước khi coi là hoàn chỉnh, để có số liệu thật đưa vào tài liệu DR Plan và Runbook
- File này nên được cập nhật song song khi thiết kế API chi tiết (`docs/api-spec.md`) và Data Model (`docs/data-model.md`), vì 3 tài liệu này có liên quan chặt chẽ với nhau

