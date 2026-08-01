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
│   └── cicd/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── staging/
│   │   └── (cấu trúc tương tự dev)
│   └── prod/
│       └── (cấu trúc tương tự dev)
├── global/
│   └── bootstrap/          (tạo S3 backend + DynamoDB lock table — chỉ chạy 1 lần)
└── README.md
```

---

## 3. Chi tiết từng module

### 3.1. `modules/network/`

**Chịu trách nhiệm:** VPC, subnet, route table, NAT, Internet Gateway, VPC Endpoint (nếu áp dụng theo câu hỏi mở ở IAM Design).

```
modules/network/
├── main.tf          (VPC, subnet, IGW, NAT, route table)
├── variables.tf
├── outputs.tf
└── README.md
```

**Input chính:** `vpc_cidr`, `az_count`, `public_subnet_cidrs`, `private_subnet_cidrs`, `environment`

**Output chính:** `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `nat_instance_ids`

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

**Chịu trách nhiệm:** RDS PostgreSQL (Multi-AZ), DynamoDB table `MatchEvents`.

```
modules/database/
├── rds.tf
├── dynamodb.tf
├── variables.tf
├── outputs.tf
└── README.md
```

**Input chính:** `vpc_id`, `private_subnet_ids`, `db_instance_class`, `multi_az` (bool), `environment`

**Output chính:** `rds_endpoint`, `rds_secret_arn` (nếu tạo secret ngay trong module này), `dynamodb_table_name`, `dynamodb_table_arn`

---

### 3.4. `modules/storage/`

**Chịu trách nhiệm:** 4 S3 bucket (raw-videos, processed-highlights, raw-tracking-data, curated-data), lifecycle policy, CloudFront distribution, WAF.

```
modules/storage/
├── s3-buckets.tf
├── lifecycle-policies.tf
├── cloudfront.tf
├── waf.tf
├── variables.tf
├── outputs.tf
└── README.md
```

**Input chính:** `environment`, `raw_video_retention_days`, `domain_name` (cho CloudFront/Route 53)

**Output chính:** `raw_videos_bucket_name`, `processed_highlights_bucket_name`, `raw_tracking_bucket_name`, `curated_data_bucket_name`, `cloudfront_distribution_id`, `cloudfront_domain_name`

---

### 3.5. `modules/messaging/`

**Chịu trách nhiệm:** SQS Queue (video-processing-jobs), Dead Letter Queue, Lambda Job Dispatcher, S3 Event Notification config.

```
modules/messaging/
├── sqs.tf
├── lambda-dispatcher.tf
├── s3-event-trigger.tf
├── variables.tf
├── outputs.tf
└── README.md
```

**Input chính:** `raw_videos_bucket_arn`, `environment`, `max_receive_count` (cho DLQ), `visibility_timeout`

**Output chính:** `sqs_queue_url`, `sqs_queue_arn`, `dlq_arn`, `dispatcher_lambda_arn`

---

### 3.6. `modules/security/`

**Chịu trách nhiệm:** toàn bộ IAM Role/Policy đã thiết kế ở IAM & Security Design, Secrets Manager secret, Security Hub, AWS Config, GuardDuty.

```
modules/security/
├── iam-backend-role.tf
├── iam-worker-role.tf
├── iam-dispatcher-role.tf
├── iam-glue-role.tf
├── iam-cicd-role.tf        (bao gồm OIDC provider config cho GitHub Actions)
├── secrets-manager.tf
├── security-hub.tf
├── aws-config.tf
├── guardduty.tf
├── variables.tf
├── outputs.tf
└── README.md
```

**Input chính:** danh sách resource ARN cụ thể mà từng role cần quyền truy cập (nhận từ output của các module khác — network, storage, database, messaging)

**Output chính:** `backend_task_role_arn`, `worker_task_role_arn`, `dispatcher_role_arn`, `glue_role_arn`, `cicd_role_arn`

**Ghi chú quan trọng:** module này phụ thuộc (depends_on) vào output của storage/database/messaging vì cần biết chính xác ARN resource để viết policy least-privilege — cần chú ý thứ tự apply hoặc dùng `data` source hợp lý để tránh circular dependency.

---

### 3.7. `modules/observability/`

**Chịu trách nhiệm:** CloudWatch Dashboard, Alarm, SNS Topic.

```
modules/observability/
├── cloudwatch-dashboard.tf
├── cloudwatch-alarms.tf
├── sns.tf
├── variables.tf
├── outputs.tf
└── README.md
```

**Input chính:** tên các resource cần giám sát (ECS service name, SQS queue name, RDS identifier, ALB arn), `alert_email` hoặc `slack_webhook_url`

**Output chính:** `sns_topic_arn`, `dashboard_url`

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
  source   = "../../modules/network"
  vpc_cidr = var.vpc_cidr
  az_count = 2
  environment = var.environment
}

module "storage" {
  source      = "../../modules/storage"
  environment = var.environment
}

module "database" {
  source             = "../../modules/database"
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  multi_az           = var.environment == "prod" ? true : false
  environment        = var.environment
}

module "messaging" {
  source                = "../../modules/messaging"
  raw_videos_bucket_arn = module.storage.raw_videos_bucket_arn
  environment           = var.environment
}

module "security" {
  source                     = "../../modules/security"
  raw_videos_bucket_arn      = module.storage.raw_videos_bucket_arn
  processed_highlights_arn   = module.storage.processed_highlights_bucket_arn
  sqs_queue_arn              = module.messaging.sqs_queue_arn
  dynamodb_table_arn         = module.database.dynamodb_table_arn
  environment                = var.environment
}

module "compute" {
  source                 = "../../modules/compute"
  vpc_id                 = module.network.vpc_id
  private_subnet_ids     = module.network.private_subnet_ids
  public_subnet_ids      = module.network.public_subnet_ids
  backend_task_role_arn  = module.security.backend_task_role_arn
  worker_task_role_arn   = module.security.worker_task_role_arn
  environment             = var.environment
}

module "observability" {
  source      = "../../modules/observability"
  environment = var.environment
}
```

**Nhận xét:** cách viết này thể hiện rõ thứ tự phụ thuộc tự nhiên — `network` và `storage` không phụ thuộc ai, `database`/`messaging` phụ thuộc `network`/`storage`, `security` phụ thuộc gần như tất cả (vì cần ARN cụ thể), `compute` phụ thuộc `security` (cần Task Role) và `network`.

---

## 5. Quản lý State

### 5.1. Backend configuration

```hcl
# environments/{env}/backend.tf
terraform {
  backend "s3" {
    bucket         = "matchlens-terraform-state"
    key            = "environments/{env}/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "matchlens-terraform-locks"
    encrypt        = true
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
- Resource name pattern: `matchlens-${var.environment}-${resource_purpose}` (đồng bộ với Naming Convention sẽ chốt chi tiết ở tài liệu riêng)
- Tag bắt buộc áp dụng qua `default_tags` ở provider block, không set tag thủ công từng resource:
```hcl
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "MatchLens"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
```

---

## 7. Thứ tự triển khai khuyến nghị khi bắt đầu code

1. `global/bootstrap/` — tạo S3 backend + DynamoDB lock (chạy 1 lần, dùng local state tạm thời cho chính bootstrap này)
2. `modules/network/` — nền tảng cho mọi thứ khác
3. `modules/storage/` — không phụ thuộc network, có thể làm song song
4. `modules/database/` — phụ thuộc network
5. `modules/messaging/` — phụ thuộc storage (cần bucket ARN)
6. `modules/security/` — phụ thuộc storage, database, messaging (cần ARN cụ thể để viết IAM policy)
7. `modules/compute/` — phụ thuộc network, security (cần Task Role ARN)
8. `modules/observability/` — phụ thuộc compute, database, messaging (cần tên resource để tạo alarm)
9. `modules/cicd/` — có thể làm độc lập, tích hợp sau cùng khi bắt đầu build pipeline

Thứ tự này khớp với Phase 0/1 trong roadmap tổng thể của dự án — bắt đầu code Terraform theo đúng thứ tự trên sẽ tránh được lỗi phụ thuộc chéo giữa các module.

---

## 8. Câu hỏi còn mở — cần quyết định trước khi code

- [ ] Dùng Terraform Workspace hay giữ nguyên cách tách thư mục `environments/{env}/` như thiết kế này? (khuyến nghị giữ tách thư mục — rõ ràng hơn, tránh rủi ro chạy nhầm workspace)
- [ ] Version Terraform và AWS Provider cụ thể nào sẽ pin trong `versions.tf` của từng module, để tránh lỗi không tương thích khi các thành viên khác (hoặc chính bạn sau này) chạy lại?
- [ ] Có cần module `modules/analytics/` riêng cho Glue/Athena/QuickSight ngay từ bây giờ, hay gộp tạm vào `modules/storage/` cho tới khi triển khai Phase 6 (Analytics)? — khuyến nghị: tạo sẵn thư mục rỗng có README ghi chú "sẽ triển khai ở Phase 6" để cấu trúc tổng thể không bị đổi giữa chừng

---

## 9. Việc cần làm tiếp theo

Sau khi chốt cấu trúc Terraform, bước tiếp theo trong giai đoạn thiết kế là **Naming Convention & Tagging Standard** (`docs/naming-tagging-standard.md`) — thực ra đã được phác thảo sơ bộ ở mục 6 của tài liệu này, cần tài liệu hóa đầy đủ và chi tiết hơn thành file riêng để tham chiếu xuyên suốt dự án.

