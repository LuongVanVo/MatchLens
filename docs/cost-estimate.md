# MatchLens — Cost Estimate

> Ước tính chi phí AWS sơ bộ theo từng service chính, dựa trên toàn bộ kiến trúc đã thiết kế. Mục tiêu: có con số tham chiếu trước khi deploy thật, thiết lập Budget Alert hợp lý, và có kịch bản tiết kiệm chi phí trong giai đoạn phát triển/demo. Đây là tài liệu cuối cùng của giai đoạn thiết kế.

---

## 1. Giả định phạm vi để ước tính

- Môi trường ước tính: **dev** (môi trường dùng nhiều nhất trong giai đoạn phát triển)
- Region: `ap-southeast-1` (Singapore) — gần Việt Nam nhất, giá thường nhỉnh hơn `us-east-1` một chút
- Khối lượng sử dụng giả định: build/test/demo trong khoảng 1 tháng, khoảng 20-30 video test (mỗi video 5-10 phút, không phải cả trận 90 phút, để tiết kiệm chi phí xử lý AI)
- Không tính chi phí Free Tier (giả định tài khoản đã qua giai đoạn free tier 12 tháng, để có con số an toàn hơn khi lập budget thực tế)

---

## 2. Ước tính chi phí theo từng service

### 2.1. Compute — ECS Fargate

| Thành phần | Cấu hình giả định | Ước tính chi phí/tháng |
|---|---|---|
| Backend API Service | 0.5 vCPU / 1GB RAM, chạy 24/7, 1 task | ~$15-18 |
| AI Worker Service | 1 vCPU / 2GB RAM, chỉ chạy khi có job (autoscale từ 0), ước tính 20-30 giờ xử lý/tháng | ~$5-8 |

**Ghi chú:** Worker nên cấu hình autoscale về 0 khi không có job trong SQS, tránh trả tiền 24/7 cho tài nguyên không dùng — đây là điểm tối ưu quan trọng nhất trong toàn bộ hệ thống vì Worker là phần tốn tài nguyên nhất khi chạy AI inference.

### 2.2. Database — RDS PostgreSQL

| Thành phần | Cấu hình giả định | Ước tính chi phí/tháng |
|---|---|---|
| RDS Master | `db.t3.micro`, Single-AZ cho dev (Multi-AZ chỉ bật ở staging/prod) | ~$12-15 |
| Storage | 20GB gp3 | ~$2-3 |
| Backup storage | Trong ngưỡng miễn phí (bằng dung lượng DB) | $0 |
| RDS Read Replica | **KHÔNG tạo ở dev** (quyết định Q3) — chỉ staging/prod | dev: $0 |

**Ghi chú (cập nhật theo Decision Record Q3, Q34):**
- Multi-AZ ở môi trường dev là không cần thiết và tốn gấp đôi chi phí RDS — chỉ bật Multi-AZ ở `staging`/`prod` để test failover, còn `dev` dùng Single-AZ.
- **Read Replica KHÔNG deploy ở dev** (tiết kiệm ~$14/tháng). Ở dev, cả 2 biến `DATABASE_URL_MASTER` và `DATABASE_URL_REPLICA` cùng trỏ về endpoint Master duy nhất — code Backend vẫn đúng kiến trúc (2 PrismaClient), chỉ khác giá trị biến môi trường. Read Replica vật lý (`matchlens-{env}-postgres-replica`) chỉ tạo ở staging/prod qua biến Terraform `create_read_replica = true`, thêm **~$14/tháng** cho mỗi môi trường đó.

### 2.3. Storage — S3

| Bucket | Ước tính dung lượng | Ước tính chi phí/tháng |
|---|---|---|
| raw-videos | ~5-10GB (video test, có lifecycle xóa sau 30-90 ngày) | ~$0.2-0.3 |
| processed-highlights | ~1-2GB (clip `raw-clips/` + bản transcode `clips/`) | ~$0.05-0.1 |
| raw-tracking-data | ~500MB-1GB (JSON/batch tracking data) | ~$0.02 |
| curated-data | ~100-200MB (Parquet, đã nén tốt) | ~$0.01 |
| athena-results (quyết định Q30) | <100MB (lifecycle xóa sau 7 ngày) | ~$0.01 |
| **Request cost (PUT/GET)** | Ước tính vài nghìn request/tháng trong giai đoạn test | ~$1-2 |

**Ghi chú:** bucket `processed-highlights` chứa **2 bản** mỗi clip (`raw-clips/` do Worker ghi + `clips/` do MediaConvert ghi) — nên cân nhắc lifecycle rule xóa prefix `raw-clips/` sau 7 ngày để không lưu trữ trùng lặp lâu dài.

### 2.3.1. ECR (Container Registry)

| Thành phần | Ước tính | Ước tính chi phí/tháng |
|---|---|---|
| ECR storage | 2 repo (backend ~300MB/image, worker ~2GB/image do PyTorch+YOLO), giữ ~10 image gần nhất | ~$1-2.5 |

**Ghi chú:** image Worker nặng do bundle PyTorch/Ultralytics — nên cấu hình **ECR Lifecycle Policy** giữ tối đa 10 image gần nhất, tránh tích lũy vô hạn qua mỗi lần CI/CD build.

### 2.4. Media Processing — AWS MediaConvert

| Thành phần | Ước tính khối lượng | Ước tính chi phí/tháng |
|---|---|---|
| Transcode | 20-30 video x 5-10 phút = ~150-300 phút video | ~$3-6 (MediaConvert tính theo phút output, giá dao động theo độ phân giải) |

**Ghi chú:** Đây là chi phí dễ bị đội lên nếu test với video độ phân giải cao (1080p/4K) — nên test với video 720p trong giai đoạn phát triển để giảm chi phí.

### 2.5. Messaging — SQS + Lambda

| Thành phần | Ước tính khối lượng | Ước tính chi phí/tháng |
|---|---|---|
| SQS (2 queue + 2 DLQ) | Vài trăm message/tháng (rất nhẹ) | ~$0 (trong ngưỡng gần như miễn phí) |
| Lambda × 3 (Job Dispatcher, Status Updater, MediaConvert Trigger) | Vài trăm lượt invoke, thời gian chạy ngắn | ~$0 (trong ngưỡng miễn phí Lambda) |

**Ghi chú:** số lượng queue/Lambda tăng so với thiết kế ban đầu (theo quyết định Q20, Q21) nhưng chi phí thực tế vẫn ~$0 vì khối lượng rất nhỏ. `status-updater-fn` chạy trong VPC nên có thêm ENI — không phát sinh phí riêng, nhưng cold start chậm hơn (~1-2 giây), chấp nhận được vì đây là luồng bất đồng bộ.

### 2.6. Data & Analytics

| Thành phần | Ước tính khối lượng | Ước tính chi phí/tháng |
|---|---|---|
| AWS Glue ETL Job | Chạy vài lần/tuần, mỗi lần vài phút (DPU nhỏ) | ~$3-5 |
| Amazon Athena | Query nhẹ trên dữ liệu Parquet nhỏ, tính theo dung lượng scan | ~$1-2 |
| QuickSight | 1 user (Author), gói Standard | ~$9/tháng (hoặc dùng Reader nếu chỉ xem, rẻ hơn — cân nhắc dùng Streamlit tự host miễn phí thay thế nếu muốn tiết kiệm) |

**Ghi chú:** Nếu muốn tiết kiệm chi phí ở giai đoạn demo/portfolio, có thể **thay QuickSight bằng dashboard tự build (Streamlit chạy trên chính ECS hoặc local)** — vẫn thể hiện được kỹ năng data visualization mà không tốn phí cố định hàng tháng.

### 2.7. Network

| Thành phần | Ước tính | Ước tính chi phí/tháng |
|---|---|---|
| NAT Instance | `t3.micro`, chạy 24/7 — **dev: 1 instance** (quyết định Q2) | ~$4-5 (dev) / ~$8-10 (staging/prod với 2 instance) |
| VPC Gateway Endpoint (S3 + DynamoDB) | Quyết định Q29 | **$0 — miễn phí** |
| Data Transfer Out | Ước tính nhẹ trong giai đoạn test | ~$1-3 |
| ALB | Chạy 24/7 | ~$16-18 |

**Ghi chú quan trọng:**
- Việc chọn **NAT Instance thay vì NAT Gateway** tiết kiệm đáng kể — NAT Gateway tính phí theo giờ + theo GB xử lý (~$32/tháng/AZ), trong khi NAT Instance chỉ trả tiền EC2 instance cố định.
- **Dev chỉ dùng 1 NAT Instance** (AZ-A, dùng chung cross-AZ) → giảm một nửa so với thiết kế 2 NAT ban đầu.
- **VPC Gateway Endpoint cho S3/DynamoDB hoàn toàn miễn phí** và loại bỏ traffic video hàng GB đi qua NAT — đây là điểm tối ưu chi phí quan trọng thứ hai sau việc Worker autoscale về 0. Không có Endpoint này, mỗi GB video Worker tải từ S3 đều tính phí NAT data processing.
- Secrets Manager **không có** Gateway Endpoint (chỉ Interface Endpoint ~$7/AZ/tháng) — ở dev để traffic đi qua NAT, không tạo Interface Endpoint.

### 2.8. CDN & Security

| Thành phần | Ước tính | Ước tính chi phí/tháng |
|---|---|---|
| CloudFront | Traffic nhẹ trong giai đoạn demo | ~$1-2 |
| WAF | Web ACL cơ bản + vài rule | ~$6-8 (phí cố định theo Web ACL + request) |
| Security Hub | Bật trên 1 account | ~$0.001/finding-check, thường dưới $3/tháng cho quy mô nhỏ |
| AWS Config | Theo số lượng config item được ghi nhận | ~$2-3 |
| GuardDuty | Theo lượng log phân tích (CloudTrail, VPC Flow Logs, DNS) | ~$3-5 cho tài khoản nhỏ |

### 2.9. Observability

| Thành phần | Ước tính | Ước tính chi phí/tháng |
|---|---|---|
| CloudWatch (Logs, Metrics, Alarms, Dashboard) | Khối lượng log vừa phải | ~$3-5 |
| SNS | Vài chục notification/tháng | ~$0 (gần như miễn phí) |

---

## 3. Tổng hợp ước tính chi phí hàng tháng (môi trường dev)

| Nhóm | Ước tính chi phí/tháng |
|---|---|
| Compute (ECS Fargate) | ~$20-26 |
| Database (RDS Master, Single-AZ, **không Replica**) | ~$14-18 |
| Storage (S3, 5 bucket) | ~$1.5-2.5 |
| ECR (container registry) | ~$1-2.5 |
| Media Processing (MediaConvert) | ~$3-6 |
| Messaging (SQS × 2 + DLQ × 2 + Lambda × 3) | ~$0 |
| Data & Analytics (Glue + Athena + QuickSight) | ~$13-16 |
| Network (1 NAT + ALB + Data Transfer, Gateway Endpoint $0) | ~$21-26 |
| CDN & Security (CloudFront + WAF + Security Hub + Config + GuardDuty) | ~$12-18 |
| Observability (CloudWatch + SNS + Budget) | ~$3-5 |
| **Tổng ước tính (dev, chạy 24/7)** | **~$89-120/tháng** |

**Chi phí bổ sung cho staging/prod:** mỗi môi trường thêm **~$14/tháng** cho Read Replica vật lý + **~$12-15/tháng** nếu bật Multi-AZ + **~$4-5/tháng** cho NAT Instance thứ hai (quyết định Q2, Q3, Q34).

### 3.1. Sàn cứng — phần KHÔNG giảm được bằng auto-shutdown

Đây là điểm cần hiểu rõ trước khi đặt Budget Alert. Các thành phần sau **tính phí theo giờ tồn tại của resource**, không theo mức sử dụng, nên việc scale ECS về 0 hay stop RDS **không làm giảm**:

| Thành phần | Chi phí/tháng | Auto-shutdown (Q33) có giúp? |
|---|---|---|
| ALB | ~$16-18 | ❌ Tính phí theo giờ ALB tồn tại, độc lập số task ECS |
| NAT Instance t3.micro (dev: 1) | ~$4-5 | ❌ Trừ khi stop cả EC2 instance |
| RDS storage 20GB gp3 | ~$2-3 | ❌ RDS ở trạng thái `stopped` vẫn tính phí storage |
| WAF Web ACL | ~$6-8 | ❌ Phí cố định theo Web ACL |
| **Sàn cứng tối thiểu** | **~$28-34/tháng** | |

Auto-shutdown chỉ giảm được phần **ECS Fargate compute** (~$20-26) và **RDS instance-hour** (~$12-15) — tức khoảng 50% tổng chi phí, đúng như kỳ vọng ở Q33, nhưng không thể xuống dưới sàn cứng.

---

## 4. Kịch bản tối ưu chi phí trong giai đoạn phát triển/demo

| Biện pháp | Tiết kiệm được ở đâu |
|---|---|
| **Auto-shutdown dev hàng đêm** (EventBridge, quyết định Q33/D4): 00:00 giờ VN scale ECS → 0 + stop RDS; 08:00 start lại | Giảm ~50% chi phí ECS + RDS instance-hour |
| **Tắt hạ tầng khi không dùng dài ngày** (`terraform destroy` cuối tuần / khi nghỉ nhiều ngày, `apply` lại khi cần) | Đây là cách duy nhất giảm được **sàn cứng** (ALB, NAT, WAF, RDS storage) |
| Worker autoscale về 0 khi SQS rỗng | Giảm phần lớn chi phí ECS Fargate cho Worker |
| **VPC Gateway Endpoint cho S3/DynamoDB** (quyết định Q29) | Loại bỏ phí NAT data processing cho traffic video hàng GB — miễn phí, hiệu quả cao |
| Dùng NAT Instance thay NAT Gateway, dev chỉ 1 instance | Tiết kiệm ~$25-30/tháng so với 2 NAT Gateway |
| Giới hạn video test ngắn (5-10 phút, độ phân giải 720p) | Giảm chi phí MediaConvert và S3 storage |
| Thay QuickSight bằng dashboard tự build (Streamlit/React) | Tiết kiệm ~$9/tháng phí cố định |
| RDS Single-AZ + không Read Replica ở dev | Giảm ~50% chi phí RDS ở môi trường dùng nhiều nhất |
| ECR Lifecycle Policy giữ tối đa 10 image | Tránh tích lũy image cũ qua mỗi lần CI/CD build |
| Lifecycle xóa prefix `raw-clips/` sau 7 ngày, `athena-results` sau 7 ngày | Tránh lưu trữ trùng lặp và kết quả query rác |

**Khuyến nghị thực tế:** kết hợp **auto-shutdown hàng đêm** (tự động, không cần nhớ) với **destroy khi nghỉ dài ngày** (thủ công, xử lý phần sàn cứng). Riêng auto-shutdown đã là điểm cộng tốt cho CV ("thiết lập cost-aware automation bằng EventBridge Scheduler, giảm ~50% chi phí môi trường dev").

---

## 5. Thiết lập AWS Budget Alert

**Ngân sách chốt: $50/tháng** (quyết định Q33).

| Ngưỡng | Số tiền | Hành động |
|---|---|---|
| 50% | $25 | Gửi email cảnh báo, không cần hành động ngay |
| 80% | $40 | Gửi email cảnh báo, rà soát resource nào đang chạy không cần thiết |
| 100% | $50 | Gửi email + cân nhắc `terraform destroy` môi trường dev |

**Lý do chọn $50 thay vì $15:** sàn cứng của hạ tầng dev đã là ~$28-34/tháng (xem mục 3.1) và auto-shutdown không giảm được phần này. Đặt ngưỡng $15 sẽ khiến alarm bắn 100% ngay trong tuần đầu tiên và trở thành **cảnh báo vô nghĩa** — mất luôn tác dụng phát hiện chi phí bất thường thật sự. Con số $50 khớp với ước tính "thực tế $30-50" và cho phép giữ hạ tầng đầy đủ (ALB + WAF + CloudFront + 3-tier VPC) để portfolio thể hiện đúng kiến trúc production.

**Cấu hình cụ thể:**
- Tạo **AWS Budget** loại "Cost Budget", tên `matchlens-{env}-monthly-budget`, ngưỡng theo tháng
- Gắn Budget filter theo tag `Project=MatchLens` để tách riêng khỏi chi phí AWS khác trong cùng account
- Kết nối notification qua SNS Topic đã có (`matchlens-{env}-alerts-topic`) để dùng chung hạ tầng thông báo với Observability

---

## 6. Câu hỏi còn mở — ĐÃ CHỐT

| Câu hỏi | Quyết định | Mã ADR |
|---|---|---|
| Ngân sách tối đa? | **$50/tháng**, alert ở 50% / 80% / 100% | Q33 |
| Có tự động destroy/shutdown dev cuối ngày? | **Có** — EventBridge 2 rule: 00:00 VN stop (ECS→0 + RDS stop), 08:00 VN start | Q33, D4 |
| Read Replica tính vào chi phí dev? | **Không** — dev không tạo Replica vật lý; chỉ staging/prod, +~$14/tháng mỗi môi trường | Q3, Q34 |
| Có dùng AWS Free Tier? | **Chưa xác định** — nếu account còn trong 12 tháng đầu, chi phí RDS/Lambda/CloudFront giảm đáng kể so với ước tính trên (ước tính này đã cố tình bỏ qua Free Tier để có con số an toàn) | — |

Chi tiết đầy đủ: `docs/decision-record.md`.

---

## 7. Tổng kết — Giai đoạn thiết kế đã hoàn thành

Với tài liệu này, toàn bộ **Design Phase** của MatchLens đã hoàn tất đầy đủ 8 hạng mục:

1. ✅ Kiến trúc hạ tầng (Architecture)
2. ✅ System Flows
3. ✅ Data Model
4. ✅ API Design
5. ✅ IAM & Security Design
6. ✅ Terraform Module Structure
7. ✅ Naming Convention & Tagging Standard
8. ✅ CI/CD Design
9. ✅ Cost Estimate

**Bước tiếp theo:** chuyển sang giai đoạn triển khai thật (Phase 0 trong roadmap tổng thể — nền tảng ứng dụng cơ bản), bắt đầu bằng việc code `global/bootstrap/` (S3 backend + DynamoDB lock) và `modules/network/` theo đúng thứ tự đã xác định ở Terraform Module Structure mục 7.

