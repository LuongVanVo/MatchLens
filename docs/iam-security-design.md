# MatchLens — IAM & Security Design

> Thiết kế chi tiết phân quyền IAM cho từng service theo nguyên tắc least-privilege, dựa trên API Design (`docs/api-spec.md`) và Data Model (`docs/data-model.md`) đã chốt. Kèm threat model sơ bộ và danh sách secret cần quản lý.

---

## 1. Nguyên tắc thiết kế chung

- Mỗi service có 1 IAM Role riêng, không dùng chung role giữa các service khác chức năng
- Không dùng wildcard `*` trên Action hoặc Resource trừ khi thực sự không thể giới hạn hơn (và phải ghi rõ lý do trong policy comment)
- Ưu tiên giới hạn theo resource cụ thể (ARN chính xác) thay vì theo service chung chung
- Dùng resource-based condition (S3 prefix, DynamoDB LeadingKeys) khi có thể, để chuẩn bị nền tảng cho multi-tenancy chặt chẽ hơn sau này
- Không hardcode credential trong code/image — toàn bộ secret qua Secrets Manager, IAM Role gắn trực tiếp vào ECS Task Definition (không dùng access key tĩnh)

---

## 2. Danh sách service cần IAM Role

| Service | Vai trò | Chạy ở đâu |
|---|---|---|
| Backend API Service | Xử lý request từ user, đọc/ghi RDS, tạo presigned URL, đọc DynamoDB/Athena | ECS Fargate |
| AI Worker Service | Poll SQS, đọc video từ S3, ghi kết quả ra S3/DynamoDB | ECS Fargate |
| Lambda — Job Dispatcher | Nhận S3 Event, đẩy message vào SQS | Lambda |
| Glue ETL Job | Đọc raw-tracking-data, ghi curated-data, cập nhật Catalog | AWS Glue |
| GitHub Actions (CI/CD) | Build, push image lên ECR, deploy ECS | External (qua OIDC) |

---

## 3. Ma trận IAM chi tiết theo từng service

### 3.1. Backend API Service Role (`matchlens-{env}-backend-role`)

| Quyền | Resource | Lý do |
|---|---|---|
| `s3:PutObject` (chỉ để generate presigned URL, không thực thi trực tiếp) | `arn:aws:s3:::matchlens-{env}-raw-videos/*` | Tạo presigned URL cho client upload |
| `s3:GetObject` | `arn:aws:s3:::matchlens-{env}-processed-highlights/*` | Lấy link video khi trả về `/highlights` (nếu không dùng CloudFront signed URL) |
| `dynamodb:Query` | `arn:aws:dynamodb:*:*:table/MatchEvents` | Đọc danh sách highlight theo `match_id` |
| `athena:StartQueryExecution`, `athena:GetQueryResults` | Athena workgroup `matchlens-{env}` | Truy vấn chỉ số cầu thủ cho `/stats` (nếu không cache sẵn) |
| `secretsmanager:GetSecretValue` | `arn:aws:secretsmanager:*:*:secret:matchlens-{env}-db-credentials-*` | Lấy DB password khi khởi động |
| `rds-db:connect` (nếu dùng IAM DB Auth) hoặc kết nối qua Secrets Manager | RDS instance cụ thể | Kết nối PostgreSQL |
| `logs:CreateLogStream`, `logs:PutLogEvents` | Log group riêng của service | Ghi log về CloudWatch |

**Không cấp:**
- Không có quyền `s3:DeleteObject` trên bất kỳ bucket nào — Backend không có lý do nghiệp vụ để xóa file trực tiếp
- Không có quyền truy cập SQS Queue — đây là việc của Lambda và Worker, Backend không tương tác trực tiếp với queue
- Không có quyền `iam:*` hay tự thay đổi policy của chính nó

---

### 3.2. AI Worker Service Role (`matchlens-{env}-worker-role`)

| Quyền | Resource | Lý do |
|---|---|---|
| `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` | `arn:aws:sqs:*:*:matchlens-{env}-video-processing-jobs` | Poll và consume job |
| `s3:GetObject` | `arn:aws:s3:::matchlens-{env}-raw-videos/*` | Tải video gốc để xử lý |
| `s3:PutObject` | `arn:aws:s3:::matchlens-{env}-processed-highlights/*` | Ghi clip đã cắt |
| `s3:PutObject` | `arn:aws:s3:::matchlens-{env}-raw-tracking-data/*` | Ghi dữ liệu tracking thô |
| `dynamodb:PutItem` | `arn:aws:dynamodb:*:*:table/MatchEvents` | Ghi metadata sự kiện detect được |
| `secretsmanager:GetSecretValue` | Secret riêng nếu Worker cần thông tin gì thêm | Chỉ nếu thực sự cần |
| `logs:CreateLogStream`, `logs:PutLogEvents` | Log group riêng | Ghi log |

**Không cấp:**
- Không có quyền truy cập bucket `curated-data` — đây là output của Glue, không phải Worker
- Không có quyền đọc RDS — Worker không cần biết thông tin user/team, chỉ xử lý theo `match_id` nhận từ SQS message
- Không có quyền `sqs:SendMessage` — Worker chỉ tiêu thụ job, không tạo job mới

---

### 3.3. Lambda — Job Dispatcher Role (`matchlens-{env}-dispatcher-role`)

| Quyền | Resource | Lý do |
|---|---|---|
| `s3:GetObject` (chỉ đọc metadata, không tải toàn bộ file) | `arn:aws:s3:::matchlens-{env}-raw-videos/*` | Xác thực file vừa upload hợp lệ |
| `sqs:SendMessage` | `arn:aws:sqs:*:*:matchlens-{env}-video-processing-jobs` | Đẩy job vào queue |
| `logs:CreateLogStream`, `logs:PutLogEvents` | Log group riêng của Lambda | Ghi log |

**Không cấp:**
- Không có quyền ghi vào bất kỳ bucket nào — Lambda này chỉ điều phối, không xử lý dữ liệu
- Không có quyền truy cập DynamoDB/RDS

---

### 3.4. Glue ETL Job Role (`matchlens-{env}-glue-role`)

| Quyền | Resource | Lý do |
|---|---|---|
| `s3:GetObject`, `s3:ListBucket` | `arn:aws:s3:::matchlens-{env}-raw-tracking-data/*` | Đọc dữ liệu tracking thô |
| `s3:PutObject` | `arn:aws:s3:::matchlens-{env}-curated-data/*` | Ghi dữ liệu đã xử lý (Parquet) |
| `glue:GetTable`, `glue:UpdateTable`, `glue:CreatePartition` | Glue Database `matchlens_{env}` | Cập nhật Data Catalog |
| `logs:CreateLogStream`, `logs:PutLogEvents` | Log group riêng | Ghi log |

**Không cấp:**
- Không có quyền truy cập bucket `raw-videos` hay `processed-highlights` — Glue chỉ làm việc với dữ liệu tracking, không liên quan tới video

---

### 3.5. GitHub Actions — CI/CD Role (`matchlens-{env}-cicd-role`, qua OIDC Federation)

| Quyền | Resource | Lý do |
|---|---|---|
| `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage` | ECR repository cụ thể của Backend và Worker | Push image sau khi build |
| `ecs:UpdateService`, `ecs:DescribeServices` | ECS Cluster/Service cụ thể của từng env | Deploy image mới |
| `iam:PassRole` (chỉ với Task Role cụ thể, không phải toàn bộ IAM) | Task Execution Role của ECS | Cho phép ECS dùng đúng role khi chạy task |

**Ghi chú bảo mật quan trọng:** Dùng **OIDC Federation** giữa GitHub Actions và AWS thay vì lưu access key/secret key dạng static trong GitHub Secrets — đây là best practice hiện tại được AWS khuyến nghị, tránh rủi ro lộ credential dài hạn.

**Không cấp:**
- Không có quyền deploy trực tiếp lên production nếu chưa qua approval — role cho môi trường prod nên tách riêng, chỉ được assume sau khi GitHub Environment protection rule cho phép

---

## 4. Secrets Manager — Danh sách secret cần quản lý

| Secret name | Nội dung | Ai được đọc |
|---|---|---|
| `matchlens-{env}-db-credentials` | Username, password RDS | Backend API Service |
| `matchlens-{env}-jwt-secret` | Khóa ký JWT | Backend API Service |
| (Tùy chọn) `matchlens-{env}-media-convert-config` | Nếu cần config riêng cho MediaConvert | Worker/MediaConvert IAM Role |

**Quy tắc xoay vòng (rotation):**
- DB credentials: bật automatic rotation của Secrets Manager nếu dùng RDS (Secrets Manager hỗ trợ rotation Lambda có sẵn cho PostgreSQL)
- JWT secret: rotation thủ công định kỳ (không tự động vì ảnh hưởng tới toàn bộ session đang hoạt động, cần có kế hoạch invalidate token cũ)

---

## 5. Threat Model sơ bộ

| Điểm nguy cơ | Rủi ro | Biện pháp phòng ngừa |
|---|---|---|
| Presigned URL bị lộ/chia sẻ | Người ngoài upload file độc hại thay vì video thật | Giới hạn thời gian hiệu lực URL ngắn (ví dụ 15 phút), giới hạn `content-type` và `content-length` khi tạo URL, quét virus/định dạng sau khi nhận qua Lambda trước khi đưa vào pipeline xử lý chính |
| IDOR (user truy cập dữ liệu team/match không thuộc về mình) | Lộ dữ liệu giữa các đội bóng khác nhau | Middleware kiểm tra `owner_id` ở mọi endpoint, đã nêu ở API Design mục 8 |
| SQS message bị xử lý lặp lại (duplicate) | Video bị xử lý AI 2 lần, tốn chi phí compute | Cấu hình SQS visibility timeout hợp lý, Worker cần idempotent (kiểm tra `match_id` đã có kết quả detect chưa trước khi ghi đè) |
| Lambda Job Dispatcher bị gọi với payload giả (không qua S3 Event thật) | Tạo job giả, gây tốn tài nguyên Worker | Lambda chỉ trigger từ S3 Event Notification cấu hình cứng, không expose qua API Gateway public |
| IAM Role của CI/CD bị lạm dụng nếu OIDC config sai | Deploy trái phép lên production | Giới hạn OIDC trust policy chỉ cho phép đúng GitHub repo + branch cụ thể, không để mở cho mọi repo |
| RDS truy cập trực tiếp từ ngoài VPC | Rò rỉ dữ liệu người dùng | RDS đặt trong Private Subnet, Security Group chỉ cho phép traffic từ Security Group của ECS service, không mở public endpoint |
| Log chứa thông tin nhạy cảm (password, token) | Rò rỉ qua CloudWatch Logs | Áp dụng log filtering/masking ở tầng ứng dụng trước khi ghi log, không log toàn bộ request body có chứa password/token |

---

## 6. Security Hub / Config / GuardDuty — Baseline áp dụng

| Dịch vụ | Cấu hình áp dụng |
|---|---|
| Security Hub | Bật CIS AWS Foundations Benchmark làm standard mặc định |
| AWS Config | Rule bắt buộc: S3 bucket không public, SG không mở 0.0.0.0/0 vào port SSH/RDP, RDS không public accessible, IAM password policy đủ mạnh |
| GuardDuty | Bật toàn bộ finding type mặc định, đặc biệt chú ý finding liên quan IAM (UnauthorizedAccess, CredentialAccess) |

---

## 7. Câu hỏi còn mở — cần quyết định trước khi code

- [ ] Có cần dùng **VPC Endpoint** cho S3/DynamoDB (thay vì traffic đi qua NAT Instance ra internet) để tăng bảo mật và giảm chi phí NAT không?
- [ ] JWT secret nên lưu ở Secrets Manager hay dùng cơ chế asymmetric key (RS256) để tách biệt việc ký và xác thực token giữa các service trong tương lai?
- [ ] Có cần Permission Boundary áp cho toàn bộ IAM Role trong tài khoản để giới hạn quyền tối đa, phòng trường hợp policy bị cấu hình sai vượt dự kiến không? (khuyến nghị có, dù dự án nhỏ — đây cũng là điểm cộng thể hiện tư duy governance khi đưa vào CV)
- [ ] Việc quét virus/nội dung độc hại cho video upload (đề cập ở Threat Model) sẽ dùng dịch vụ nào — tự viết Lambda kiểm tra cơ bản hay tích hợp ClamAV/dịch vụ bên thứ ba?

---

## 8. Việc cần làm tiếp theo

Sau khi chốt IAM & Security Design, bước tiếp theo trong giai đoạn thiết kế là **Terraform Module Structure** (`docs/terraform-structure.md`) — để chuyển hóa toàn bộ IAM Role, resource đã liệt kê ở đây thành cấu trúc code cụ thể, module hóa rõ ràng.

