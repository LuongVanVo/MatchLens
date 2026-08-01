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
| RDS Instance | `db.t3.micro`, Single-AZ cho dev (Multi-AZ chỉ bật ở prod) | ~$12-15 |
| Storage | 20GB gp3 | ~$2-3 |
| Backup storage | Trong ngưỡng miễn phí (bằng dung lượng DB) | $0 |

**Ghi chú:** Multi-AZ ở môi trường dev là không cần thiết và tốn gấp đôi chi phí RDS — chỉ nên bật Multi-AZ ở `staging`/`prod` để test tính năng failover, còn `dev` dùng Single-AZ.

### 2.3. Storage — S3

| Bucket | Ước tính dung lượng | Ước tính chi phí/tháng |
|---|---|---|
| raw-videos | ~5-10GB (video test, có lifecycle xóa sau 30-90 ngày) | ~$0.2-0.3 |
| processed-highlights | ~1-2GB (clip đã cắt, dung lượng nhỏ hơn video gốc) | ~$0.05 |
| raw-tracking-data | ~500MB-1GB (JSON/batch tracking data) | ~$0.02 |
| curated-data | ~100-200MB (Parquet, đã nén tốt) | ~$0.01 |
| **Request cost (PUT/GET)** | Ước tính vài nghìn request/tháng trong giai đoạn test | ~$1-2 |

### 2.4. Media Processing — AWS MediaConvert

| Thành phần | Ước tính khối lượng | Ước tính chi phí/tháng |
|---|---|---|
| Transcode | 20-30 video x 5-10 phút = ~150-300 phút video | ~$3-6 (MediaConvert tính theo phút output, giá dao động theo độ phân giải) |

**Ghi chú:** Đây là chi phí dễ bị đội lên nếu test với video độ phân giải cao (1080p/4K) — nên test với video 720p trong giai đoạn phát triển để giảm chi phí.

### 2.5. Messaging — SQS + Lambda

| Thành phần | Ước tính khối lượng | Ước tính chi phí/tháng |
|---|---|---|
| SQS | Vài trăm message/tháng (rất nhẹ) | ~$0 (trong ngưỡng gần như miễn phí) |
| Lambda (Job Dispatcher) | Vài trăm lượt invoke, thời gian chạy ngắn | ~$0 (trong ngưỡng miễn phí Lambda) |

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
| NAT Instance | `t3.micro`, chạy 24/7 x 2 AZ | ~$8-10 (rẻ hơn nhiều so với NAT Gateway ~$32/tháng/AZ + data processing fee) |
| Data Transfer Out | Ước tính nhẹ trong giai đoạn test | ~$1-3 |
| ALB | Chạy 24/7 | ~$16-18 |

**Ghi chú quan trọng:** Việc chọn **NAT Instance thay vì NAT Gateway** (đã quyết định từ kiến trúc ban đầu, kế thừa từ dự án Ghost blog) tiết kiệm đáng kể — NAT Gateway tính phí theo giờ + theo GB xử lý, trong khi NAT Instance chỉ trả tiền EC2 instance cố định, phù hợp cho dự án cá nhân/demo.

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
| Database (RDS) | ~$14-18 |
| Storage (S3) | ~$1.5-2.5 |
| Media Processing (MediaConvert) | ~$3-6 |
| Messaging (SQS + Lambda) | ~$0 |
| Data & Analytics (Glue + Athena + QuickSight) | ~$13-16 |
| Network (NAT + ALB + Data Transfer) | ~$25-31 |
| CDN & Security (CloudFront + WAF + Security Hub + Config + GuardDuty) | ~$12-18 |
| Observability (CloudWatch + SNS) | ~$3-5 |
| **Tổng ước tính** | **~$92-123/tháng** |

**Ghi chú quan trọng:** Đây là ước tính cho việc chạy **liên tục 24/7 trong 1 tháng** ở mức tối thiểu. Trong thực tế triển khai dự án cá nhân, bạn hoàn toàn có thể giảm đáng kể chi phí này bằng các biện pháp ở mục 4 — với cách làm hợp lý, chi phí thực tế mỗi tháng có thể chỉ còn khoảng **$30-50** hoặc thấp hơn.

---

## 4. Kịch bản tối ưu chi phí trong giai đoạn phát triển/demo

| Biện pháp | Tiết kiệm được ở đâu |
|---|---|
| **Tắt hạ tầng khi không dùng** (chạy `terraform destroy` sau mỗi buổi code, `terraform apply` lại khi cần) | Tiết kiệm gần như toàn bộ chi phí compute/network trong thời gian không làm việc |
| Worker autoscale về 0 khi SQS rỗng | Giảm phần lớn chi phí ECS Fargate cho Worker |
| Dùng NAT Instance thay NAT Gateway | Đã áp dụng — tiết kiệm ~$20-25/tháng so với NAT Gateway |
| Giới hạn video test ngắn (5-10 phút, độ phân giải 720p) | Giảm chi phí MediaConvert và S3 storage |
| Thay QuickSight bằng dashboard tự build (Streamlit) | Tiết kiệm ~$9/tháng phí cố định |
| RDS Single-AZ ở dev, chỉ Multi-AZ ở staging/prod khi cần test failover | Giảm ~50% chi phí RDS ở môi trường dùng nhiều nhất |
| Xóa S3 object test không cần thiết định kỳ (lifecycle policy đã thiết kế) | Tránh tích lũy storage cost không cần thiết theo thời gian |
| Chỉ bật Security Hub/Config/GuardDuty ở 1 account duy nhất (không nhân bản cho nhiều môi trường) trong giai đoạn học tập | Giảm chi phí governance nếu chưa cần multi-account thật sự |

**Khuyến nghị thực tế:** Vì đây là dự án cá nhân phục vụ học tập/portfolio (không phải hệ thống chạy thật cho khách hàng), nên **áp dụng triệt để việc destroy hạ tầng khi không dùng tới** — đây cũng là thói quen tốt để đưa vào CV ("chủ động tối ưu chi phí hạ tầng trong quá trình phát triển bằng cách teardown môi trường không sử dụng").

---

## 5. Thiết lập AWS Budget Alert

| Ngưỡng | Hành động |
|---|---|
| 50% ngân sách dự kiến (ví dụ $25 nếu đặt mục tiêu $50/tháng) | Gửi email cảnh báo, không cần hành động ngay |
| 80% ngân sách dự kiến | Gửi email cảnh báo, kiểm tra lại resource nào đang chạy không cần thiết |
| 100% ngân sách dự kiến | Gửi email + cân nhắc tạm dừng resource không thiết yếu (dùng script destroy môi trường dev) |

**Cấu hình cụ thể:**
- Tạo **AWS Budget** loại "Cost Budget", đặt ngưỡng theo tháng
- Gắn Budget theo tag `Project=MatchLens` để tách riêng khỏi chi phí AWS khác (nếu account có dùng cho việc khác)
- Kết nối notification qua SNS Topic đã có sẵn (`matchlens-{env}-alerts-topic`) để dùng chung hạ tầng thông báo với Observability, không cần tạo kênh riêng

---

## 6. Câu hỏi còn mở — cần quyết định trước khi code

- [ ] Ngân sách tối đa chấp nhận được cho toàn bộ quá trình làm dự án (từ lúc bắt đầu tới khi hoàn thiện portfolio) là bao nhiêu? — nên chốt con số cụ thể để đặt Budget Alert chính xác thay vì ước tính chung chung
- [ ] Có dùng AWS Free Tier (nếu tài khoản còn trong 12 tháng đầu) không? Nếu có, một số chi phí ở trên (RDS, Lambda, CloudFront) sẽ giảm đáng kể hoặc về $0
- [ ] Có cần thiết lập cơ chế tự động destroy môi trường dev vào cuối ngày (qua Lambda + EventBridge Schedule) để tránh quên tắt thủ công không? — đây là điểm hay có thể thêm vào như 1 tính năng nhỏ thể hiện tư duy cost-awareness

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

