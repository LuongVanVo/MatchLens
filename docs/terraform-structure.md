# MatchLens — Terraform Module Structure

> Thiết kế cấu trúc code Terraform, module hóa theo từng nhóm hạ tầng đã thiết kế ở các tài liệu trước (Architecture, Data Model, IAM & Security). Mục tiêu: tái sử dụng được giữa các environment (dev/staging/prod), dễ maintain, tách rõ trách nhiệm từng module.

---

## 1. Nguyên tắc thiết kế

- Mỗi module chỉ chịu trách nhiệm cho **1 nhóm resource logic** (network, compute, database...), không gộp lung tung
- Module nhận input qua `variables.tf`, xuất giá trị cần dùng ở nơi khác qua `outputs.tf` — không hardcode giá trị chéo giữa các module
- Tách biệt hoàn toàn `modules/` (code tái sử dụng, không chứa giá trị cụ thể môi trường nào) và `environments/` (nơi gọi module với giá trị cụ thể cho từng env)
- Remote state lưu trên S3 + khóa qua DynamoDB, tách state theo từng environment để tránh 1 lỗi ảnh hưởng toàn bộ hệ thống
- Naming convention và tagging áp dụng nhất quán ngay từ module gốc (không để tới environment mới xử lý)

---

## 2. Cây thư mục tổng thể

```
matchlens-infra/
├── modules/
│   ├── network/
│   ├── compute/
│   ├── database/
│   ├── storage/
│   ├── messaging/
│   ├── security/
│   ├── observability/
│   ├── cicd/
│   └── analytics/          (chỉ có README — reserved cho Phase 6, quyết định Q6)
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   ├── versions.tf
│   │   └── backend.tf
│   ├── staging/
│   │   └── (cấu trúc tương tự dev)
│   └── prod/
│       └── (cấu trúc tương tự dev)
├── global/
│   └── bootstrap/          (tạo S3 backend + DynamoDB lock table — chỉ chạy 1 lần)
└── README.md
```

**Số module chính thức: 8** (`network`, `compute`, `database`, `storage`, `messaging`, `security`, `observability`, `cicd`) + 1 stub `analytics/` chưa có `.tf` (quyết định Q5, Q6).

---

## 3. Chi tiết từng module

### 3.1. `modules/network/`

**Chịu trách nhiệm:** VPC, subnet 3 tier, route table, NAT Instance, Internet Gateway, VPC Gateway Endpoint.

```
modules/network/
├── main.tf          (VPC, subnet 3 tier, IGW, route table)
├── nat-instance.tf  (NAT Instance, số lượng theo var.nat_instance_count)
├── vpc-endpoints.tf (Gateway Endpoint cho S3 + DynamoDB — quyết định Q29)
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

**Kiến trúc 3-Tier bắt buộc** (quyết định Q1): `public`, `private_app`, `private_db`. Route table của `private_db` **không có** route `0.0.0.0/0`.

**Input chính:** `vpc_cidr`, `az_count`, `public_subnet_cidrs`, `private_app_subnet_cidrs`, `private_db_subnet_cidrs`, `nat_instance_count` (dev = 1, staging/prod = 2 — quyết định Q2), `environment`

**Output chính:** `vpc_id`, `public_subnet_ids`, `private_app_subnet_ids`, `private_db_subnet_ids`, `nat_instance_ids`, `db_subnet_group_name`

---

### 3.2. `modules/compute/`

**Chịu trách nhiệm:** ECS Cluster, ECS Service + Task Definition cho Backend API và AI Worker, ALB, Target Group, Auto Scaling policy.

```
modules/compute/
├── main.tf
├── ecs-backend.tf     (Task Definition + Service riêng cho Backend)
├── ecs-worker.tf      (Task Definition + Service riêng cho Worker)
├── alb.tf
├── autoscaling.tf
├── variables.tf
├── outputs.tf
└── README.md
```

**Input chính:** `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `backend_image_uri`, `worker_image_uri`, `backend_task_role_arn`, `worker_task_role_arn`, `environment`

**Output chính:** `alb_dns_name`, `ecs_cluster_name`, `backend_service_name`, `worker_service_name`

**Ghi chú:** tách file riêng cho backend và worker (`ecs-backend.tf`, `ecs-worker.tf`) dù cùng 1 module, vì 2 service có cấu hình autoscaling và resource sizing khác nhau hẳn (Worker cần nhiều CPU/Memory hơn cho AI inference).

---

### 3.3. `modules/database/`

**Chịu trách nhiệm:** RDS PostgreSQL (Master, Multi-AZ Standby, Read Replica có điều kiện), DynamoDB table `match-events`.

```
modules/database/
├── rds.tf
├── rds-replica.tf   (count = var.create_read_replica ? 1 : 0 — quyết định Q3)
├── dynamodb.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

**Input chính:** `vpc_id`, `private_db_subnet_ids`, `db_instance_class`, `multi_az` (bool), `create_read_replica` (bool — dev = false, staging/prod = true), `environment`

**Output chính:** `rds_master_endpoint`, `rds_replica_endpoint` (bằng `rds_master_endpoint` khi `create_read_replica = false`), `rds_secret_arn`, `dynamodb_table_name`, `dynamodb_table_arn`

**Identifier** (quyết định Q4): Master = `matchlens-{env}-postgres`, Read Replica = `matchlens-{env}-postgres-replica`.

---

### 3.4. `modules/storage/`

**Chịu trách nhiệm:** 5 S3 bucket (raw-videos, processed-highlights, raw-tracking-data, curated-data, athena-results), lifecycle policy, CloudFront distribution + OAC + key group, WAF.

```
modules/storage/
├── s3-buckets.tf
├── lifecycle-policies.tf
├── cloudfront.tf           (1 distribution, 2 origin, OAC)
├── cloudfront-signing.tf   (aws_cloudfront_public_key + key_group — quyết định Q23)
├── waf.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

**Bucket thứ 5** `matchlens-{env}-athena-results` (quyết định Q30): lifecycle xoá vĩnh viễn sau 7 ngày.

**Input chính:** `environment`, `raw_video_retention_days`, `domain_name` (cho CloudFront/Route 53), `cloudfront_public_key_pem`

**Output chính:** `raw_videos_bucket_name/arn`, `processed_highlights_bucket_name/arn`, `raw_tracking_bucket_name/arn`, `curated_data_bucket_name/arn`, `athena_results_bucket_name/arn`, `cloudfront_distribution_id`, `cloudfront_domain_name`, `cloudfront_key_group_id`

---

### 3.5. `modules/messaging/`

**Chịu trách nhiệm:** SQS Queue + DLQ (2 cặp), 3 Lambda function, S3 Event Notification config.

```
modules/messaging/
├── sqs-video-jobs.tf        (video-processing-jobs + DLQ)
├── sqs-status-callbacks.tf  (match-status-callbacks + DLQ — quyết định Q20, D2)
├── lambda-dispatcher.tf     (job dispatcher)
├── lambda-status-updater.tf (ghi RDS — trong Private App Subnet, quyết định Q20)
├── lambda-mediaconvert.tf   (mediaconvert-trigger-fn — quyết định Q21)
├── s3-event-trigger.tf      (2 notification: raw-videos, và processed-highlights prefix raw-clips/)
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

**Cấu hình chốt** (quyết định Q28): `max_receive_count = 3`, `visibility_timeout = 900` giây cho cả 2 queue.

**Lưu ý S3 Event Notification** (quyết định Q19b): notification trên bucket `processed-highlights` **bắt buộc** có `filter_prefix = "raw-clips/"`. MediaConvert ghi output vào prefix `clips/` nên không khớp filter → không thể tự kích hoạt đệ quy. Đây là biện pháp chống vòng lặp ở tầng hạ tầng, không phụ thuộc logic Lambda.

**Input chính:** `raw_videos_bucket_arn`, `processed_highlights_bucket_arn`, `environment`, `max_receive_count`, `visibility_timeout`, `private_app_subnet_ids`, `status_updater_role_arn`, `dispatcher_role_arn`, `mediaconvert_trigger_role_arn`, `mediaconvert_role_arn`, `db_secret_arn`

**Output chính:** `sqs_queue_url/arn`, `dlq_arn`, `status_callbacks_queue_url/arn`, `status_callbacks_dlq_arn`, `dispatcher_lambda_arn`, `status_updater_lambda_arn`, `mediaconvert_trigger_lambda_arn`

---

### 3.6. `modules/security/`

**Chịu trách nhiệm:** toàn bộ IAM Role/Policy đã thiết kế ở IAM & Security Design, Secrets Manager secret, Security Hub, AWS Config, GuardDuty.

```
modules/security/
├── iam-backend-role.tf
├── iam-worker-role.tf
├── iam-dispatcher-role.tf
├── iam-status-updater-role.tf      (quyết định Q20)
├── iam-mediaconvert-role.tf        (trigger role + service role — quyết định Q21)
├── iam-glue-role.tf
├── iam-cicd-role.tf                (OIDC provider có thể đặt ở modules/cicd)
├── secrets-manager.tf              (db-credentials, jwt-keypair, cloudfront-signing-key)
├── security-hub.tf
├── aws-config.tf
├── guardduty.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

**Input chính:** danh sách resource ARN cụ thể mà từng role cần quyền truy cập (nhận từ output của các module khác — network, storage, database, messaging)

**Output chính:** `backend_task_role_arn`, `worker_task_role_arn`, `dispatcher_role_arn`, `status_updater_role_arn`, `mediaconvert_trigger_role_arn`, `mediaconvert_role_arn`, `glue_role_arn`, `cicd_role_arn`, `db_secret_arn`, `jwt_keypair_secret_arn`, `cloudfront_signing_key_secret_arn`

**Ghi chú quan trọng:** module này phụ thuộc (depends_on) vào output của storage/database/messaging vì cần biết chính xác ARN resource để viết policy least-privilege — cần chú ý thứ tự apply hoặc dùng `data` source hợp lý để tránh circular dependency.

**Vấn đề circular dependency giữa `security` và `messaging`:** `messaging` cần role ARN để gắn vào Lambda, nhưng `security` cần queue ARN để viết policy. Giải pháp: `security` viết policy theo **ARN dự đoán được** (`arn:aws:sqs:{region}:{account_id}:matchlens-{env}-match-status-callbacks`) dựng từ `data.aws_caller_identity` + naming convention, thay vì tham chiếu trực tiếp output của `messaging`. Nhờ vậy `security` apply trước `messaging` được.

---

### 3.7. `modules/observability/`

**Chịu trách nhiệm:** CloudWatch Dashboard, Alarm, SNS Topic, AWS Budget, EventBridge auto-shutdown (dev).

```
modules/observability/
├── cloudwatch-dashboard.tf
├── cloudwatch-alarms.tf
├── sns.tf
├── budget.tf              (AWS Budget $50/tháng — quyết định Q33)
├── eventbridge-shutdown.tf (2 rule stop/start dev — quyết định D4)
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

**Alarm bắt buộc:** SQS DLQ có message (cả 2 DLQ — `video-processing-dlq` và `match-status-callbacks-dlq`), ECS service health check fail, RDS storage vượt ngưỡng, ALB 5xx rate, Glue Job fail (Phase 6).

**EventBridge auto-shutdown** — chỉ áp dụng `dev`, cần **2 rule** vì RDS chỉ có stop/start (không có "pause", xem D4):
- `0 17 * * ? *` UTC (00:00 giờ VN) → ECS desired count = 0, `StopDBInstance`
- `0 1 * * ? *` UTC (08:00 giờ VN) → `StartDBInstance`, ECS desired count = 1

Rule start là **bắt buộc** vì AWS tự động start lại RDS sau tối đa 7 ngày dù không ai can thiệp — có rule chủ động thì thời điểm start nằm trong kiểm soát.

**Input chính:** tên các resource cần giám sát (ECS service name, SQS queue name, RDS identifier, ALB arn), `alert_email` hoặc `slack_webhook_url`, `monthly_budget_usd` (= 50), `enable_auto_shutdown` (bool — chỉ true ở dev)

**Output chính:** `sns_topic_arn`, `dashboard_url`

---

### 3.9. `modules/analytics/` (stub — Phase 6)

Chỉ có `README.md` ghi chú *"Reserved for Phase 6 (Glue / Athena / QuickSight)"*, chưa có file `.tf` nào (quyết định Q6). Mục đích: giữ cấu trúc thư mục tổng thể không bị đổi giữa chừng khi tới Phase 6.

---

### 3.8. `modules/cicd/`

**Chịu trách nhiệm:** ECR repository, GitHub OIDC Identity Provider (nếu không đặt chung với security module).

```
modules/cicd/
├── ecr.tf
├── github-oidc.tf
├── variables.tf
├── outputs.tf
└── README.md
```

**Input chính:** `github_org`, `github_repo`, `environment`

**Output chính:** `ecr_backend_repo_url`, `ecr_worker_repo_url`

---

## 4. Cấu trúc `environments/{env}/main.tf` — cách các module được gọi

Mỗi environment chỉ là nơi "lắp ráp" các module lại với giá trị cụ thể, không chứa logic hạ tầng trực tiếp:

```hcl
module "network" {
  source                   = "../../modules/network"
  vpc_cidr                 = var.vpc_cidr
  az_count                 = 2
  nat_instance_count       = var.nat_instance_count   # dev = 1, staging/prod = 2
  environment              = var.environment
}

module "storage" {
  source      = "../../modules/storage"
  environment = var.environment
}

module "database" {
  source                = "../../modules/database"
  vpc_id                = module.network.vpc_id
  private_db_subnet_ids = module.network.private_db_subnet_ids
  multi_az              = var.environment == "dev" ? false : true
  create_read_replica   = var.environment == "dev" ? false : true
  environment           = var.environment
}

module "security" {
  source                     = "../../modules/security"
  raw_videos_bucket_arn      = module.storage.raw_videos_bucket_arn
  processed_highlights_arn   = module.storage.processed_highlights_bucket_arn
  raw_tracking_bucket_arn    = module.storage.raw_tracking_bucket_arn
  curated_data_bucket_arn    = module.storage.curated_data_bucket_arn
  athena_results_bucket_arn  = module.storage.athena_results_bucket_arn
  dynamodb_table_arn         = module.database.dynamodb_table_arn
  cloudfront_key_group_id    = module.storage.cloudfront_key_group_id
  environment                = var.environment
  # SQS ARN dựng từ naming convention, không tham chiếu module.messaging
  # → tránh circular dependency (xem mục 3.6)
}

module "messaging" {
  source                          = "../../modules/messaging"
  raw_videos_bucket_arn           = module.storage.raw_videos_bucket_arn
  processed_highlights_bucket_arn = module.storage.processed_highlights_bucket_arn
  private_app_subnet_ids          = module.network.private_app_subnet_ids
  dispatcher_role_arn             = module.security.dispatcher_role_arn
  status_updater_role_arn         = module.security.status_updater_role_arn
  mediaconvert_trigger_role_arn   = module.security.mediaconvert_trigger_role_arn
  mediaconvert_role_arn           = module.security.mediaconvert_role_arn
  db_secret_arn                   = module.security.db_secret_arn
  max_receive_count               = 3
  visibility_timeout              = 900
  environment                     = var.environment
}

module "compute" {
  source                  = "../../modules/compute"
  vpc_id                  = module.network.vpc_id
  private_app_subnet_ids  = module.network.private_app_subnet_ids
  public_subnet_ids       = module.network.public_subnet_ids
  backend_task_role_arn   = module.security.backend_task_role_arn
  worker_task_role_arn    = module.security.worker_task_role_arn
  environment             = var.environment
}

module "observability" {
  source               = "../../modules/observability"
  monthly_budget_usd   = 50
  enable_auto_shutdown = var.environment == "dev" ? true : false
  environment          = var.environment
}
```

**Nhận xét:** thứ tự phụ thuộc — `network` và `storage` không phụ thuộc ai; `database` phụ thuộc `network`; `security` phụ thuộc `storage`/`database` (và dựng SQS ARN theo convention để không phụ thuộc `messaging`); `messaging` phụ thuộc `storage`/`network`/`security`; `compute` phụ thuộc `network`/`security`.

---

## 5. Quản lý State

### 5.1. Backend configuration

```hcl
# environments/{env}/backend.tf
terraform {
  backend "s3" {
    bucket         = "matchlens-terraform-state-{aws_account_id}"
    key            = "environments/{env}/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "matchlens-terraform-locks"
    encrypt        = true
  }
}
```

**Quyết định Q8:** bucket state có hậu tố `{aws_account_id}` để đảm bảo globally unique. Region toàn dự án là `ap-southeast-1` (Singapore).

### 5.2. Pin version (quyết định Q7)

Mỗi module và mỗi environment đều có `versions.tf`:

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
```

### 5.2. Nguyên tắc
- Mỗi environment có **1 state file riêng biệt** (`key` khác nhau) — không dùng chung state cho dev/staging/prod để tránh 1 lỗi terraform apply ảnh hưởng chéo môi trường
- Bucket S3 chứa state cần bật versioning + encryption, không public
- DynamoDB table dùng để lock state, tránh 2 người `apply` cùng lúc gây conflict
- Bootstrap resource này (S3 bucket + DynamoDB table) nằm ở `global/bootstrap/`, chạy **thủ công 1 lần duy nhất** trước khi các environment khác có thể dùng remote backend (vì bản thân backend cần tồn tại trước khi Terraform có thể dùng nó)

---

## 6. Quy ước đặt tên biến & resource (áp dụng xuyên suốt mọi module)

- Biến môi trường luôn tên `environment`, giá trị: `dev`, `staging`, `prod`
- Resource name pattern: `matchlens-${var.environment}-${resource_purpose}` (chi tiết đầy đủ ở `docs/naming-tagging-standard.md`)
- Tag bắt buộc áp dụng qua `default_tags` ở provider block, không set tag thủ công từng resource:
```hcl
provider "aws" {
  region = var.aws_region       # ap-southeast-1
  default_tags {
    tags = {
      Project     = "MatchLens"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner   # "luong-van-vo"
      CostCenter  = "matchlens-project"
    }
  }
}
```

---

## 7. Thứ tự triển khai khuyến nghị khi bắt đầu code

1. `global/bootstrap/` — tạo S3 backend + DynamoDB lock (chạy 1 lần, dùng local state tạm thời cho chính bootstrap này, sau đó migrate state lên S3)
2. `modules/network/` — nền tảng cho mọi thứ khác (VPC 3-tier + Gateway Endpoint)
3. `modules/storage/` — không phụ thuộc network, có thể làm song song
4. `modules/database/` — phụ thuộc network (cần `private_db_subnet_ids`)
5. `modules/security/` — phụ thuộc storage, database (cần ARN cụ thể để viết IAM policy). SQS ARN dựng theo naming convention để không phụ thuộc `messaging`
6. `modules/messaging/` — phụ thuộc storage, network, security (cần role ARN gắn vào Lambda)
7. `modules/compute/` — phụ thuộc network, security (cần Task Role ARN)
8. `modules/observability/` — phụ thuộc compute, database, messaging (cần tên resource để tạo alarm)
9. `modules/cicd/` — có thể làm độc lập, tích hợp sau cùng khi bắt đầu build pipeline

**Lưu ý thay đổi so với bản thiết kế trước:** `security` (bước 5) giờ đứng **trước** `messaging` (bước 6) — vì `messaging` cần role ARN để gắn vào 3 Lambda function, còn `security` chỉ cần ARN dự đoán được của SQS queue (dựng từ account ID + naming convention). Đây là cách phá vỡ circular dependency phát sinh từ quyết định Q20.

Thứ tự này khớp với Phase 0/1 trong `docs/roadmap.md`.

---

## 8. Câu hỏi còn mở — ĐÃ CHỐT TOÀN BỘ

| Câu hỏi | Quyết định | Mã ADR |
|---|---|---|
| Terraform Workspace hay tách thư mục `environments/{env}/`? | Giữ tách thư mục — rõ ràng hơn, tránh chạy nhầm workspace | — |
| Pin version Terraform + AWS Provider? | `required_version = "~> 1.9"`, `hashicorp/aws = "~> 5.60"` | Q7 |
| Có `modules/analytics/` ngay không? | Tạo stub chỉ có README, ghi chú reserved cho Phase 6 | Q6 |

Chi tiết đầy đủ: `docs/decision-record.md`.

---

## 9. Việc cần làm tiếp theo

Sau khi chốt cấu trúc Terraform, bước tiếp theo trong giai đoạn thiết kế là **Naming Convention & Tagging Standard** (`docs/naming-tagging-standard.md`) — thực ra đã được phác thảo sơ bộ ở mục 6 của tài liệu này, cần tài liệu hóa đầy đủ và chi tiết hơn thành file riêng để tham chiếu xuyên suốt dự án.

