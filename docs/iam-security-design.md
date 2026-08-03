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

| Service | Vai trò | Chạy ở đâu | Role name |
|---|---|---|---|
| Backend API Service | Xử lý request, đọc/ghi RDS, tạo presigned URL, đọc DynamoDB, sinh CloudFront Signed URL | ECS Fargate | `matchlens-{env}-backend-role` |
| AI Worker Service | Poll SQS, đọc video từ S3, ghi kết quả ra S3/DynamoDB, gửi callback status | ECS Fargate | `matchlens-{env}-worker-role` |
| Lambda — Job Dispatcher | Nhận S3 Event, đẩy message vào SQS, gửi callback status | Lambda | `matchlens-{env}-dispatcher-role` |
| **Lambda — Status Updater** | **Compute duy nhất ngoài Backend có RDS credential** — đọc callback queue, UPDATE `matches.status` | Lambda (trong VPC, Private App Subnet) | `matchlens-{env}-status-updater-role` |
| **Lambda — MediaConvert Trigger** | Nhận S3 Event prefix `raw-clips/`, tạo MediaConvert job | Lambda | `matchlens-{env}-mediaconvert-trigger-role` |
| **MediaConvert Service Role** | Role MediaConvert assume để đọc `raw-clips/`, ghi `clips/` | MediaConvert | `matchlens-{env}-mediaconvert-role` |
| Glue ETL Job | Đọc raw-tracking-data, ghi curated-data, cập nhật Catalog | AWS Glue | `matchlens-{env}-glue-role` |
| GitHub Actions (CI/CD) | Build, push image lên ECR, deploy ECS | External (qua OIDC) | `matchlens-{env}-cicd-role` |

**3 role mới** so với thiết kế ban đầu, phát sinh từ quyết định Q20 (Event-Driven Status Callback) và Q21 (MediaConvert qua Lambda riêng).

---

## 3. Ma trận IAM chi tiết theo từng service

### 3.1. Backend API Service Role (`matchlens-{env}-backend-role`)

| Quyền | Resource | Lý do |
|---|---|---|
| `s3:PutObject` (chỉ để generate presigned URL, không thực thi trực tiếp) | `arn:aws:s3:::matchlens-{env}-raw-videos/*` | Tạo presigned URL cho client upload |
| `dynamodb:Query` | `arn:aws:dynamodb:*:*:table/matchlens-{env}-match-events` | Đọc danh sách highlight theo `match_id` |
| `athena:StartQueryExecution`, `athena:GetQueryExecution`, `athena:GetQueryResults` | Athena workgroup `matchlens-{env}-workgroup` | Truy vấn chỉ số cầu thủ cho `/stats` (Phase 6) |
| `s3:GetObject`, `s3:ListBucket` | `arn:aws:s3:::matchlens-{env}-curated-data/*` | Athena đọc dữ liệu Parquet dưới danh nghĩa caller (Phase 6) |
| `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` | `arn:aws:s3:::matchlens-{env}-athena-results/*` | Athena ghi kết quả query — bắt buộc phải có (quyết định Q30) |
| `glue:GetTable`, `glue:GetPartitions`, `glue:GetDatabase` | Glue Database `matchlens_{env}` | Athena cần đọc Catalog để biết schema (Phase 6) |
| `secretsmanager:GetSecretValue` | `arn:aws:secretsmanager:*:*:secret:matchlens-{env}-db-credentials-secret-*` | Lấy DB password khi khởi động |
| `secretsmanager:GetSecretValue` | `arn:aws:secretsmanager:*:*:secret:matchlens-{env}-jwt-keypair-secret-*` | Lấy RS256 keypair để ký/verify JWT (quyết định Q33, D3) |
| `secretsmanager:GetSecretValue` | `arn:aws:secretsmanager:*:*:secret:matchlens-{env}-cloudfront-signing-key-secret-*` | Lấy private key sinh CloudFront Signed URL (quyết định Q23) |
| `logs:CreateLogStream`, `logs:PutLogEvents` | `arn:aws:logs:*:*:log-group:/matchlens/{env}/backend:*` | Ghi log về CloudWatch |

**Không cấp:**
- ❌ `s3:DeleteObject` trên bất kỳ bucket nào — Backend không có lý do nghiệp vụ để xóa file trực tiếp (dùng soft-delete ở RDS, dọn S3 bằng lifecycle policy)
- ❌ **`s3:GetObject` trên `processed-highlights`** — **đã bỏ so với thiết kế ban đầu** (quyết định Q23): khi dùng CloudFront OAC + Signed URL, Backend chỉ cần ký URL bằng private key, **không** cần quyền đọc S3. Đây là ví dụ tốt về việc thiết kế bảo mật đúng giúp **thu hẹp** quyền
- ❌ Mọi quyền SQS — Backend không tương tác với queue nào (ghi RDS trực tiếp cho 2 transition đầu, phần còn lại do Lambda)
- ❌ `iam:*` hay tự thay đổi policy của chính nó

---

### 3.2. AI Worker Service Role (`matchlens-{env}-worker-role`)

| Quyền | Resource | Lý do |
|---|---|---|
| `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` | `arn:aws:sqs:*:*:matchlens-{env}-video-processing-jobs` | Poll và consume job |
| **`sqs:SendMessage`** | **`arn:aws:sqs:*:*:matchlens-{env}-match-status-callbacks`** — **CHỈ queue này** | Gửi callback báo `completed`/`failed` (quyết định Q20). Xem ghi chú bên dưới |
| `s3:GetObject` | `arn:aws:s3:::matchlens-{env}-raw-videos/*` | Tải video gốc để xử lý |
| `s3:PutObject` | `arn:aws:s3:::matchlens-{env}-processed-highlights/raw-clips/*` | Ghi clip thô — **giới hạn đúng prefix `raw-clips/`**, không cho ghi vào `clips/` (đó là địa hạt của MediaConvert) |
| `s3:PutObject` | `arn:aws:s3:::matchlens-{env}-raw-tracking-data/*` | Ghi dữ liệu tracking thô |
| `dynamodb:PutItem` | `arn:aws:dynamodb:*:*:table/matchlens-{env}-match-events` | Ghi metadata sự kiện + marker idempotency |
| **`dynamodb:GetItem`, `dynamodb:Query`** | `arn:aws:dynamodb:*:*:table/matchlens-{env}-match-events` | **Kiểm tra `MARKER#COMPLETED` trước khi xử lý** — bắt buộc để idempotent (quyết định Q21, Q22) |
| `logs:CreateLogStream`, `logs:PutLogEvents` | `arn:aws:logs:*:*:log-group:/matchlens/{env}/worker:*` | Ghi log |

> **Ghi chú về `sqs:SendMessage` — thay đổi có chủ đích so với thiết kế ban đầu:** bản thiết kế trước ghi *"không cấp `sqs:SendMessage` — Worker chỉ tiêu thụ job, không tạo job mới"*. Quyết định Q20 buộc phải nới quyền này, nhưng **giới hạn chặt vào đúng 1 ARN** là queue callback. Worker **vẫn tuyệt đối không** có `SendMessage` trên `video-processing-jobs` — nghĩa là không thể tự tạo job xử lý video mới, đúng tinh thần ban đầu. Đây là nới quyền tối thiểu cần thiết, không phải nới lỏng nguyên tắc.

**Không cấp:**
- ❌ Truy cập bucket `curated-data` — output của Glue, không phải Worker
- ❌ **Truy cập RDS** (không có `rds-db:connect`, không có secret DB) — Worker không cần biết thông tin user/team, chỉ xử lý theo `match_id` từ SQS message. Việc cập nhật `matches.status` đi qua callback queue
- ❌ `sqs:SendMessage` trên `video-processing-jobs` — không được tự tạo job mới
- ❌ `s3:PutObject` trên prefix `clips/` của `processed-highlights` — chỉ MediaConvert ghi vào đó
- ❌ `mediaconvert:*` — Worker **không** gọi MediaConvert trực tiếp (quyết định Q21)
- ❌ `dynamodb:DeleteItem` — không cần xóa vì `event_id` tất định đã đảm bảo overwrite an toàn

---

### 3.3. Lambda — Job Dispatcher Role (`matchlens-{env}-dispatcher-role`)

| Quyền | Resource | Lý do |
|---|---|---|
| `s3:GetObject`, `s3:HeadObject` | `arn:aws:s3:::matchlens-{env}-raw-videos/*` | Xác thực metadata file vừa upload (không tải toàn bộ file) |
| `sqs:SendMessage` | `arn:aws:sqs:*:*:matchlens-{env}-video-processing-jobs` | Đẩy job vào queue |
| `sqs:SendMessage` | `arn:aws:sqs:*:*:matchlens-{env}-match-status-callbacks` | Gửi callback `{status: "processing"}` (quyết định Q20) |
| `logs:CreateLogStream`, `logs:PutLogEvents` | `arn:aws:logs:*:*:log-group:/aws/lambda/matchlens-{env}-job-dispatcher-fn:*` | Ghi log |

**Không cấp:**
- ❌ Ghi vào bất kỳ bucket nào — Lambda này chỉ điều phối, không xử lý dữ liệu
- ❌ Truy cập DynamoDB/RDS

---

### 3.4. Lambda — Status Updater Role (`matchlens-{env}-status-updater-role`) — MỚI

> Đây là **compute duy nhất ngoài Backend API** có quyền ghi RDS (quyết định Q20). Chạy trong VPC (Private App Subnet) để kết nối được RDS ở Private DB Subnet.

| Quyền | Resource | Lý do |
|---|---|---|
| `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` | `arn:aws:sqs:*:*:matchlens-{env}-match-status-callbacks` | Consume callback message |
| `secretsmanager:GetSecretValue` | `arn:aws:secretsmanager:*:*:secret:matchlens-{env}-db-credentials-secret-*` | Lấy DB credential để UPDATE `matches` |
| `ec2:CreateNetworkInterface`, `ec2:DescribeNetworkInterfaces`, `ec2:DeleteNetworkInterface` | `*` (AWS yêu cầu, không thể giới hạn ARN) | **Bắt buộc** để Lambda chạy trong VPC — đây là managed policy `AWSLambdaVPCAccessExecutionRole` của AWS. Lý do dùng wildcard: AWS không hỗ trợ giới hạn ARN cho các action này |
| `logs:CreateLogStream`, `logs:PutLogEvents` | `arn:aws:logs:*:*:log-group:/aws/lambda/matchlens-{env}-status-updater-fn:*` | Ghi log |

**Không cấp:**
- ❌ Mọi quyền S3 — Lambda này chỉ ghi RDS
- ❌ DynamoDB
- ❌ `sqs:SendMessage` — chỉ consume, không phát sinh message mới

**Giới hạn ghi ở tầng ứng dụng:** Lambda chỉ được UPDATE 3 cột (`status`, `error_message`, `duration_sec`) của bảng `matches`, và chỉ với 3 giá trị status (`processing`, `completed`, `failed`). IAM không thể giới hạn ở mức cột/row, nên đây là ràng buộc phải enforce trong code Lambda + validate transition.

---

### 3.5. Lambda — MediaConvert Trigger Role (`matchlens-{env}-mediaconvert-trigger-role`) — MỚI

| Quyền | Resource | Lý do |
|---|---|---|
| `mediaconvert:CreateJob`, `mediaconvert:GetJob`, `mediaconvert:DescribeEndpoints` | `*` (MediaConvert job chưa tồn tại lúc tạo, không có ARN cụ thể để giới hạn) | Tạo transcode job |
| **`iam:PassRole`** | `arn:aws:iam::*:role/matchlens-{env}-mediaconvert-role` — **chỉ đúng 1 role này** | Cho phép MediaConvert assume service role. Giới hạn ARN chính xác là **bắt buộc** — `iam:PassRole` với `*` là lỗ hổng privilege escalation nghiêm trọng |
| `s3:HeadObject` | `arn:aws:s3:::matchlens-{env}-processed-highlights/raw-clips/*` | Kiểm tra file input tồn tại trước khi tạo job |
| `logs:CreateLogStream`, `logs:PutLogEvents` | `arn:aws:logs:*:*:log-group:/aws/lambda/matchlens-{env}-mediaconvert-trigger-fn:*` | Ghi log |

**Không cấp:** ❌ `s3:PutObject`/`GetObject` nội dung — Lambda chỉ ra lệnh, MediaConvert mới là bên đọc/ghi file. ❌ DynamoDB/RDS.

---

### 3.6. MediaConvert Service Role (`matchlens-{env}-mediaconvert-role`) — MỚI

Role này do MediaConvert assume (trust policy: `mediaconvert.amazonaws.com`), không gắn vào compute nào.

| Quyền | Resource | Lý do |
|---|---|---|
| `s3:GetObject` | `arn:aws:s3:::matchlens-{env}-processed-highlights/raw-clips/*` | Đọc clip thô làm input |
| `s3:PutObject` | `arn:aws:s3:::matchlens-{env}-processed-highlights/clips/*` | Ghi bản transcode — **giới hạn đúng prefix `clips/`** |

**Không cấp:** ❌ `s3:PutObject` trên prefix `raw-clips/` — nếu cấp, MediaConvert ghi output vào cùng prefix input sẽ **kích hoạt lại chính nó qua S3 Event → vòng lặp đệ quy vô hạn**. Việc tách prefix ở tầng IAM là lớp phòng thủ thứ hai, bổ sung cho `filter_prefix` của S3 Event Notification (quyết định Q19b).

---

### 3.7. Glue ETL Job Role (`matchlens-{env}-glue-role`)

| Quyền | Resource | Lý do |
|---|---|---|
| `s3:GetObject`, `s3:ListBucket` | `arn:aws:s3:::matchlens-{env}-raw-tracking-data/*` | Đọc dữ liệu tracking thô |
| `s3:PutObject` | `arn:aws:s3:::matchlens-{env}-curated-data/*` | Ghi dữ liệu đã xử lý (Parquet) |
| `glue:GetTable`, `glue:UpdateTable`, `glue:CreateTable`, `glue:GetPartitions`, `glue:CreatePartition`, `glue:BatchCreatePartition` | Glue Database `matchlens_{env}` | Cập nhật Data Catalog + tạo partition Hive-style (quyết định Q19) |
| `logs:CreateLogStream`, `logs:PutLogEvents` | `arn:aws:logs:*:*:log-group:/aws-glue/jobs/*` | Ghi log |

**Không cấp:**
- ❌ Truy cập `raw-videos` hay `processed-highlights` — Glue chỉ làm việc với dữ liệu tracking, không liên quan video
- ❌ RDS — nếu Phase 6 cần JOIN với `match_track_mappings`, việc đó do **Backend** làm sau khi Athena trả kết quả, không phải Glue

---

### 3.8. GitHub Actions — CI/CD Role (`matchlens-{env}-cicd-role`, qua OIDC Federation)

| Quyền | Resource | Lý do |
|---|---|---|
| `ecr:GetAuthorizationToken` | `*` (AWS yêu cầu, không hỗ trợ giới hạn ARN cho action này) | Lấy token đăng nhập ECR |
| `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage` | `arn:aws:ecr:*:*:repository/matchlens-backend`, `arn:aws:ecr:*:*:repository/matchlens-worker` | Push image sau khi build |
| `ecs:UpdateService`, `ecs:DescribeServices`, `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition` | ECS Cluster/Service cụ thể của từng env | Deploy image mới |
| `iam:PassRole` | Chỉ Task Execution Role + Task Role của ECS (`matchlens-{env}-backend-role`, `matchlens-{env}-worker-role`, execution role) — **không phải `*`** | Cho phép ECS dùng đúng role khi chạy task |

**Ghi chú bảo mật quan trọng:** Dùng **OIDC Federation** giữa GitHub Actions và AWS thay vì lưu access key/secret key static trong GitHub Secrets. Trust policy phải khóa đúng repo + branch:

```json
"Condition": {
  "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
  "StringLike": { "token.actions.githubusercontent.com:sub": "repo:{github_org}/MatchLens:ref:refs/heads/develop" }
}
```

**Không cấp:**
- ❌ Deploy trực tiếp lên production nếu chưa qua approval — role cho môi trường prod tách riêng, chỉ assume được sau khi GitHub Environment protection rule cho phép
- ❌ `iam:PassRole` với `*` — đây là lỗ hổng privilege escalation kinh điển
- ❌ Quyền truy cập dữ liệu (S3 content, RDS, DynamoDB) — CI/CD chỉ deploy, không chạm dữ liệu

---

## 3.9. Bảng tổng hợp ai chạm được RDS (quyết định Q20)

Đây là điểm kiểm soát quan trọng nhất về mặt bảo mật dữ liệu người dùng:

| Thành phần | RDS credential | Ghi chú |
|---|---|---|
| Backend API Service | ✅ Có | Đọc/ghi đầy đủ qua Prisma |
| **Lambda Status Updater** | ✅ Có | **Chỉ** UPDATE 3 cột của `matches` (enforce ở code) |
| AI Worker Service | ❌ Không | Gửi callback qua SQS |
| Lambda Job Dispatcher | ❌ Không | Gửi callback qua SQS |
| Lambda MediaConvert Trigger | ❌ Không | Không liên quan dữ liệu nghiệp vụ |
| MediaConvert Service Role | ❌ Không | Chỉ đọc/ghi S3 |
| Glue ETL Job | ❌ Không | Chỉ làm việc với S3 + Catalog |
| CI/CD Role | ❌ Không | Chỉ deploy |

**Lợi ích ngoài bảo mật:** Worker scale nhiều task đồng thời (mỗi task xử lý 1 video) — nếu mỗi task mở connection RDS riêng sẽ nhanh chóng cạn connection pool của `db.t3.micro` (max ~85 connection). Việc tập trung ghi RDS vào 1 Lambda giải quyết luôn vấn đề này.

---

## 4. Secrets Manager — Danh sách secret cần quản lý

| Secret name | Nội dung | Ai được đọc |
|---|---|---|
| `matchlens-{env}-db-credentials-secret` | Username, password RDS | Backend API Service, **Lambda Status Updater** |
| `matchlens-{env}-jwt-keypair-secret` | JSON `{ "private_key_pem": "...", "public_key_pem": "..." }` — RS256 keypair (quyết định Q33, D3) | Backend API Service |
| `matchlens-{env}-cloudfront-signing-key-secret` | Private key ký CloudFront Signed URL (quyết định Q23) | Backend API Service |

**Thay đổi so với thiết kế ban đầu:** secret `matchlens-{env}-jwt-secret` (dành cho HS256 symmetric) **đổi tên** thành `matchlens-{env}-jwt-keypair-secret` chứa cặp key RS256. Lý do chọn RS256: tách biệt việc ký (chỉ Backend cần private key) và verify (service khác chỉ cần public key) — chuẩn bị cho kiến trúc nhiều service về sau.

**Quy tắc xoay vòng (rotation):**
- DB credentials: bật automatic rotation của Secrets Manager (có Lambda rotation sẵn cho PostgreSQL)
- JWT keypair: rotation **thủ công** định kỳ — đổi keypair sẽ invalidate toàn bộ access token đang hoạt động, cần có kế hoạch (ví dụ chấp nhận user phải login lại, hoặc hỗ trợ 2 key song song trong thời gian chuyển đổi)
- CloudFront signing key: rotation thủ công, cần cập nhật cả `aws_cloudfront_public_key` trong Terraform

**Yêu cầu tagging:** cả 3 secret bắt buộc gắn `DataClassification = confidential` theo `naming-tagging-standard.md` mục 3.2.

---

## 5. Threat Model sơ bộ

| Điểm nguy cơ | Rủi ro | Biện pháp phòng ngừa |
|---|---|---|
| Presigned URL bị lộ/chia sẻ | Người ngoài upload file độc hại thay vì video thật | TTL ngắn (900s), giới hạn `content-type` (`video/mp4`, `video/quicktime`) và `content-length` (≤2GB) khi tạo URL, rate-limit 10 req/phút/user |
| IDOR (user truy cập dữ liệu team/match không thuộc về mình) | Lộ dữ liệu giữa các đội bóng khác nhau | **2 guard riêng**: `TeamOwnershipGuard` (route có `:team_id`) và `MatchOwnershipGuard` (route chỉ có `:match_id`) — cả 2 query qua Master để tránh 403 oan. Xem `backend-architecture.md` mục 7 |
| SQS message bị xử lý lặp lại (duplicate) | Video xử lý AI 2 lần (tốn compute), highlight trùng lặp | `visibility_timeout = 900s`, Worker kiểm tra `MARKER#COMPLETED` trước khi xử lý, và `event_id` **tất định** để `PutItem` overwrite thay vì tạo item mới (quyết định Q22) |
| **Vòng lặp đệ quy S3 Event → MediaConvert → S3 Event** | **Chi phí tăng vô hạn không kiểm soát** | Tách 2 prefix `raw-clips/` (input) và `clips/` (output); S3 Event filter `raw-clips/`; **và** IAM của MediaConvert role chỉ cho ghi `clips/` — 2 lớp phòng thủ độc lập (quyết định Q19b) |
| Lambda Job Dispatcher bị gọi với payload giả | Tạo job giả, tốn tài nguyên Worker | Lambda chỉ trigger từ S3 Event Notification cấu hình cứng, không expose qua API Gateway public |
| **`status-updater-fn` chết → status treo `processing` vĩnh viễn** | **Silent failure — user thấy spinner quay mãi, không ai biết** | DLQ riêng cho `match-status-callbacks` (`max_receive_count = 3`) + CloudWatch Alarm + SNS. Nguy hiểm hơn job AI fail vì không có dấu hiệu rõ ràng (quyết định D2) |
| **Callback message giả mạo** | Kẻ tấn công đánh dấu match của người khác là `completed`/`failed` | Chỉ 2 role (`worker-role`, `dispatcher-role`) có `sqs:SendMessage` trên queue callback; queue không expose public; Lambda validate transition hợp lệ trước khi UPDATE |
| Video highlight bị xem trái phép qua URL trực tiếp | Lộ video chiến thuật của đội bóng cho đối thủ | S3 `processed-highlights` **private hoàn toàn** + CloudFront OAC + **Signed URL TTL 4 giờ** (quyết định Q23). Không có object nào public |
| **`iam:PassRole` cấu hình quá rộng** | **Privilege escalation** — Lambda/CI-CD có thể pass role quyền cao hơn cho service khác | `mediaconvert-trigger-role` chỉ pass đúng `matchlens-{env}-mediaconvert-role`; `cicd-role` chỉ pass ECS task role cụ thể. **Tuyệt đối không dùng `*`** |
| IAM Role của CI/CD bị lạm dụng nếu OIDC config sai | Deploy trái phép lên production | OIDC trust policy khóa đúng GitHub repo + branch cụ thể (`repo:{org}/MatchLens:ref:refs/heads/develop`), không để mở cho mọi repo |
| RDS truy cập trực tiếp từ ngoài VPC | Rò rỉ dữ liệu người dùng | RDS đặt trong **Private DB Subnet không có route `0.0.0.0/0`** (quyết định Q1), SG chỉ cho phép traffic từ SG của ECS service và `status-updater-fn`, không mở public endpoint |
| Log chứa thông tin nhạy cảm (password, token, presigned URL) | Rò rỉ qua CloudWatch Logs | Pino redact config: loại `password`, `authorization`, `refresh_token`, `upload_url` khỏi log. **Không** log toàn bộ request body ở endpoint auth |
| Refresh token bị đánh cắp | Kẻ tấn công duy trì session vô hạn | Lưu **hash SHA-256** trong DB (không lưu token thô); rotation mỗi lần refresh; `logout` set `revoked_at` (quyết định Q12) |

---

## 6. Security Hub / Config / GuardDuty — Baseline áp dụng

| Dịch vụ | Cấu hình áp dụng |
|---|---|
| Security Hub | Bật CIS AWS Foundations Benchmark làm standard mặc định |
| AWS Config | Rule bắt buộc: S3 bucket không public, SG không mở 0.0.0.0/0 vào port SSH/RDP, RDS không public accessible, IAM password policy đủ mạnh |
| GuardDuty | Bật toàn bộ finding type mặc định, đặc biệt chú ý finding liên quan IAM (UnauthorizedAccess, CredentialAccess) |

---

## 7. Câu hỏi còn mở — ĐÃ CHỐT

| Câu hỏi | Quyết định | Mã ADR |
|---|---|---|
| Có dùng VPC Endpoint cho S3/DynamoDB? | **Có — triển khai ngay Phase 0.** Gateway Endpoint cho S3 + DynamoDB **miễn phí**, loại traffic video hàng GB khỏi NAT Instance. Secrets Manager không có Gateway Endpoint (chỉ Interface ~$7/AZ) → dev đi qua NAT | Q29 |
| JWT symmetric hay asymmetric? | **RS256 (asymmetric)** — keypair ở `matchlens-{env}-jwt-keypair-secret` | Q33, D3 |
| Có Permission Boundary cho toàn bộ IAM Role? | **Chưa triển khai ở Phase 2** — ghi nhận là hạng mục nâng cao có thể bổ sung ở Phase 7. Lý do hoãn: dự án 1 người, rủi ro policy cấu hình sai thấp; ưu tiên hoàn thiện ma trận least-privilege cơ bản trước. Nếu bổ sung, đây là điểm cộng governance rõ ràng cho CV | — |
| Quét virus video upload dùng gì? | **Chưa triển khai ở v1** — hiện chỉ validate `content-type` + `content-length` ở bước cấp presigned URL. Ghi nhận là hạng mục mở rộng (ClamAV trên Lambda hoặc Amazon GuardDuty Malware Protection for S3). Cần ghi rõ giới hạn này trong `README.md` phần Security | — |

Chi tiết đầy đủ: `docs/decision-record.md`.

**Hai hạng mục hoãn ở trên là quyết định có ý thức, không phải bỏ sót** — nên nêu chủ động khi phỏng vấn ("tôi đã nhận diện nhưng ưu tiên sau vì lý do X") thay vì để người phỏng vấn phát hiện.

---

## 8. Checklist rà soát trước khi apply IAM

- [ ] Không role nào có `Action: "*"` hoặc `Resource: "*"` ngoài 3 ngoại lệ đã ghi rõ lý do (`ecr:GetAuthorizationToken`, `ec2:*NetworkInterface` cho Lambda-in-VPC, `mediaconvert:CreateJob`)
- [ ] Mọi `iam:PassRole` đều giới hạn ARN chính xác, không dùng wildcard
- [ ] `worker-role` **không** có `sqs:SendMessage` trên `video-processing-jobs` (chỉ trên `match-status-callbacks`)
- [ ] `worker-role` **không** có `s3:PutObject` trên prefix `clips/`
- [ ] `mediaconvert-role` **không** có `s3:PutObject` trên prefix `raw-clips/` (chống vòng lặp)
- [ ] `backend-role` **không** có `s3:GetObject` trên `processed-highlights` (dùng CloudFront Signed URL thay thế)
- [ ] Chỉ đúng 2 thành phần có RDS credential: Backend API và `status-updater-fn`
- [ ] Cả 3 secret đã gắn tag `DataClassification = confidential`
- [ ] OIDC trust policy khóa đúng repo + branch, không mở cho mọi repo

---

## 9. Việc cần làm tiếp theo

IAM & Security Design này đã đồng bộ với `docs/decision-record.md`. Khi code `infra/modules/security/`, dùng bảng mục 3 làm nguồn duy nhất — không suy đoán thêm quyền, không "cấp rộng cho tiện lúc test" (quy tắc bắt buộc ở `CLAUDE.md` mục 7.1).

