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

1. HLV đã đăng nhập, tạo mới một trận đấu (match) qua Backend API — dữ liệu match được ghi vào **RDS**
2. HLV chọn video để upload → Frontend gọi endpoint `POST /matches/{id}/upload-url`
3. Request đi qua CloudFront → ALB → **Backend API Service**
4. Backend **không nhận file trực tiếp** — chỉ tạo một **presigned URL** trỏ tới **S3 Bucket (raw-videos)** và trả về cho client (luồng "returns presigned URL")
5. Client (trình duyệt của HLV) dùng presigned URL để **upload file thẳng lên S3**, không đi qua Backend hay ALB (luồng "uploads video directly using presigned URL")
6. Sau khi upload thành công, S3 sinh ra **S3 Event Notification**

**Lý do thiết kế:** tránh để Backend phải xử lý file video dung lượng lớn, giảm tải cho ECS service và chi phí truyền dữ liệu qua ALB.

**Trường hợp lỗi:**
- Presigned URL hết hạn trước khi upload xong → client cần gọi lại API để lấy URL mới
- File không đúng định dạng/vượt kích thước cho phép → nên validate ở bước tạo presigned URL (giới hạn content-type, content-length) trước khi cấp URL

---

## 3. Luồng xử lý AI bất đồng bộ — Highlight Engine (Core Async Flow)

Đây là luồng quan trọng nhất của hệ thống, xử lý hoàn toàn bất đồng bộ để không block người dùng.

1. **S3 Event Notification** (từ bước upload) kích hoạt **Lambda (Job Dispatcher)**
2. Lambda xác thực metadata cơ bản của video, tạo message mô tả job, đẩy vào **SQS Queue (video-processing-jobs)**
3. **ECS Fargate – AI Worker Service** (đang chạy sẵn hoặc được scale lên theo độ dài queue) liên tục poll và consume job từ SQS
4. Worker tải video từ S3 raw-videos, chạy inference bằng **YOLOv11** để phát hiện cầu thủ, bóng, và các sự kiện (sút, phạm lỗi, pha bóng nhanh)
5. Sau khi xử lý xong, Worker ghi dữ liệu ra 3 nơi song song:
   - **S3 Bucket (processed-highlights)**: các đoạn clip đã cắt theo sự kiện phát hiện được
   - **DynamoDB (detection metadata)**: dữ liệu nhanh về sự kiện (loại sự kiện, timestamp, match_id) để truy vấn nhanh cho tính năng highlight
   - **S3 Bucket (raw-tracking-data)**: toàn bộ dữ liệu tracking thô (tọa độ từng frame) để phục vụ phân tích sâu hơn sau này (dùng ở luồng Analytics)
6. **AWS MediaConvert** lấy clip thô từ S3 processed-highlights, transcode sang định dạng chuẩn hóa (phù hợp phát trên nhiều thiết bị), ghi kết quả trở lại cùng bucket
7. HLV mở lại trang trận đấu, gọi `GET /matches/{id}/highlights` → Backend truy vấn DynamoDB lấy danh sách clip → trả về link video
8. Client phát video qua **CloudFront Origin 2**, lấy nội dung trực tiếp từ S3 processed-highlights (đã qua MediaConvert)

**Trạng thái xử lý (polling):**
- Trong lúc chờ xử lý, client có thể gọi `GET /matches/{id}/status` định kỳ để biết job đang ở trạng thái nào: `pending` → `processing` → `completed` / `failed`

**Trường hợp lỗi:**
- Worker xử lý job thất bại (video lỗi, timeout, hết bộ nhớ) → SQS tự động retry theo cấu hình visibility timeout
- Sau số lần retry tối đa (cấu hình trước, ví dụ 3 lần) → message chuyển vào **Dead Letter Queue (SQS DLQ)**
- DLQ có message → **CloudWatch Alarm** kích hoạt → **SNS** gửi cảnh báo tới kênh Email/Slack để đội vận hành kiểm tra thủ công

---

## 4. Luồng phân tích chỉ số cầu thủ — Analytics Pipeline (Data Flow)

Luồng này chạy tách biệt, thường theo lịch (batch) chứ không real-time như highlight.

1. Dữ liệu tracking thô đã có sẵn tại **S3 Bucket (raw-tracking-data)** (được ghi ra từ bước 5 của luồng Highlight Engine — đây là cùng một bucket, dùng chung giữa 2 pipeline)
2. **AWS Glue ETL Job** chạy theo lịch (hoặc trigger thủ công), đọc dữ liệu raw, thực hiện:
   - Làm sạch dữ liệu (loại bỏ frame lỗi/nhiễu)
   - Tính toán chỉ số: quãng đường di chuyển, vị trí trung bình (heatmap), tốc độ theo từng cầu thủ
3. Kết quả ghi vào **S3 Bucket (curated-data)** dưới định dạng Parquet, đã tối ưu cho truy vấn
4. **AWS Glue Data Catalog** tự động cập nhật schema của dữ liệu curated (qua Glue Crawler)
5. **Amazon Athena** cho phép truy vấn SQL trực tiếp trên dữ liệu curated mà không cần hạ tầng database riêng
6. **QuickSight Dashboard** kết nối tới Athena, hiển thị trực quan: heatmap cầu thủ, so sánh chỉ số qua nhiều trận, chuẩn bị báo cáo đối thủ cho trận tiếp theo

**Trường hợp lỗi:**
- Glue Job thất bại (schema thay đổi bất ngờ, dữ liệu thiếu field) → cần alarm riêng trên Glue Job status, không dùng chung cơ chế DLQ như SQS
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

