# MatchLens — Naming Convention & Tagging Standard

> Chuẩn đặt tên và gắn tag áp dụng xuyên suốt toàn bộ resource AWS của dự án. Mục tiêu: dễ tìm kiếm, dễ phân biệt môi trường, hỗ trợ IAM policy theo điều kiện (tag-based access control), và phục vụ cost allocation chính xác.

---

## 1. Nguyên tắc chung

- Naming convention áp dụng nhất quán cho **mọi resource**, không có ngoại lệ trừ khi AWS giới hạn ký tự đặc biệt (ví dụ S3 bucket không cho phép chữ hoa/dấu gạch dưới)
- Tag bắt buộc được set qua `default_tags` ở Terraform provider block (đã đề cập ở Terraform Module Structure mục 6), không set tag thủ công từng resource để tránh thiếu sót
- Mọi giá trị trong tên resource dùng **chữ thường, không dấu, nối bằng dấu gạch ngang** (kebab-case) để tương thích với mọi loại resource AWS (kể cả S3, Route 53 vốn nhạy với ký tự)

---

## 2. Naming Convention

### 2.1. Format chung

```
matchlens-{environment}-{service/resource-purpose}-{resource-type}
```

| Thành phần | Giá trị cho phép | Ví dụ |
|---|---|---|
| Prefix dự án | `matchlens` (cố định) | |
| `{environment}` | `dev`, `staging`, `prod` | |
| `{service/resource-purpose}` | Mô tả ngắn gọn chức năng | `backend`, `worker`, `raw-videos` |
| `{resource-type}` | Loại resource (viết tắt chuẩn) | `ecs`, `rds`, `s3`, `role` |

### 2.2. Bảng áp dụng theo từng loại resource

| Loại resource | Pattern | Ví dụ thực tế |
|---|---|---|
| VPC | `matchlens-{env}-vpc` | `matchlens-dev-vpc` |
| Subnet | `matchlens-{env}-{public/private}-subnet-{az}` | `matchlens-dev-private-subnet-a` |
| NAT Instance | `matchlens-{env}-nat-{az}` | `matchlens-dev-nat-a` |
| Security Group | `matchlens-{env}-{purpose}-sg` | `matchlens-dev-backend-sg` |
| ALB | `matchlens-{env}-alb` | `matchlens-dev-alb` |
| ECS Cluster | `matchlens-{env}-cluster` | `matchlens-dev-cluster` |
| ECS Service | `matchlens-{env}-{backend/worker}-service` | `matchlens-dev-backend-service` |
| ECS Task Definition | `matchlens-{env}-{backend/worker}-task` | `matchlens-dev-worker-task` |
| RDS Instance | `matchlens-{env}-postgres` | `matchlens-dev-postgres` |
| DynamoDB Table | `matchlens-{env}-match-events` | `matchlens-dev-match-events` |
| S3 Bucket | `matchlens-{env}-{purpose}` (không viết tắt, S3 cần globally unique) | `matchlens-dev-raw-videos` |
| SQS Queue | `matchlens-{env}-video-processing-jobs` | `matchlens-dev-video-processing-jobs` |
| SQS DLQ | `matchlens-{env}-video-processing-dlq` | `matchlens-dev-video-processing-dlq` |
| Lambda Function | `matchlens-{env}-{purpose}-fn` | `matchlens-dev-job-dispatcher-fn` |
| IAM Role | `matchlens-{env}-{service}-role` | `matchlens-dev-backend-role` |
| IAM Policy | `matchlens-{env}-{service}-policy` | `matchlens-dev-worker-policy` |
| Secrets Manager Secret | `matchlens-{env}-{purpose}-secret` | `matchlens-dev-db-credentials-secret` |
| CloudWatch Dashboard | `matchlens-{env}-dashboard` | `matchlens-dev-dashboard` |
| CloudWatch Alarm | `matchlens-{env}-{metric}-alarm` | `matchlens-dev-sqs-dlq-alarm` |
| SNS Topic | `matchlens-{env}-alerts-topic` | `matchlens-dev-alerts-topic` |
| ECR Repository | `matchlens-{backend/worker}` (không cần env — 1 repo dùng chung nhiều môi trường, phân biệt bằng image tag) | `matchlens-backend` |
| CloudFront Distribution | Không đặt tên thủ công (AWS tự sinh ID) — dùng tag `Name` để nhận diện | Tag: `matchlens-dev-cdn` |
| Glue Job | `matchlens-{env}-etl-player-stats` | `matchlens-dev-etl-player-stats` |
| Glue Database (Catalog) | `matchlens_{env}` (dùng underscore vì Glue yêu cầu) | `matchlens_dev` |
| Athena Workgroup | `matchlens-{env}-workgroup` | `matchlens-dev-workgroup` |

### 2.3. Trường hợp đặc biệt

- **S3 Bucket**: bắt buộc globally unique toàn AWS, nếu bị trùng cần thêm hậu tố ngẫu nhiên hoặc account ID: `matchlens-dev-raw-videos-{account-id-suffix}`
- **Glue Database**: dùng `_` thay vì `-` vì Athena/Glue không hỗ trợ dấu gạch ngang trong tên database/table
- **ECR Repository**: không gắn `{env}` vào tên repo vì cùng 1 image được build 1 lần rồi promote qua các môi trường bằng tag (`dev`, `staging`, `prod`, hoặc theo git SHA) — tránh build lại image riêng cho từng môi trường

---

## 3. Tagging Standard

### 3.1. Tag bắt buộc (Mandatory) — áp dụng cho MỌI resource

| Tag Key | Giá trị | Mục đích |
|---|---|---|
| `Project` | `MatchLens` | Nhận diện dự án, phục vụ cost allocation report |
| `Environment` | `dev` / `staging` / `prod` | Phân biệt môi trường, dùng trong IAM condition nếu cần |
| `ManagedBy` | `Terraform` | Đánh dấu resource được quản lý bằng IaC, tránh sửa tay nhầm |
| `Owner` | Tên hoặc email người chịu trách nhiệm (ví dụ `luong-van-vo`) | Xác định người liên hệ khi có sự cố |
| `CostCenter` | `matchlens-project` | Phục vụ AWS Cost Explorer lọc theo tag |

### 3.2. Tag khuyến nghị (Optional nhưng nên có) — theo từng nhóm resource

| Tag Key | Áp dụng cho | Ví dụ giá trị |
|---|---|---|
| `Component` | Resource thuộc nhóm chức năng nào | `network`, `compute`, `database`, `storage`, `security` |
| `Service` | Resource gắn với service cụ thể | `backend-api`, `ai-worker`, `job-dispatcher` |
| `DataClassification` | Resource lưu dữ liệu nhạy cảm | `internal`, `confidential` (ví dụ RDS chứa user data nên đánh dấu `confidential`) |
| `Backup` | Có cần backup định kỳ không | `required`, `not-required` |

### 3.3. Ví dụ áp dụng đầy đủ tag cho 1 resource cụ thể

Ví dụ RDS instance môi trường prod:
```
Project             = MatchLens
Environment         = prod
ManagedBy           = Terraform
Owner               = luong-van-vo
CostCenter          = matchlens-project
Component           = database
DataClassification  = confidential
Backup              = required
```

---

## 4. Cách áp dụng qua Terraform (default_tags + tag riêng)

```hcl
# Áp dụng tag bắt buộc cho toàn bộ resource qua provider
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "MatchLens"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = "matchlens-project"
    }
  }
}

# Tag riêng bổ sung ở từng resource khi cần (merge thêm, không ghi đè default_tags)
resource "aws_db_instance" "postgres" {
  # ... cấu hình khác
  tags = {
    Component          = "database"
    DataClassification = "confidential"
    Backup             = "required"
  }
}
```

**Lưu ý:** `default_tags` tự động merge với `tags` khai báo riêng ở resource — không cần lặp lại tag bắt buộc ở từng resource.

---

## 5. Lợi ích thực tế của việc chuẩn hóa này (để hiểu tại sao doanh nghiệp yêu cầu)

| Lợi ích | Cách tag/naming hỗ trợ |
|---|---|
| Cost tracking chính xác theo dự án/môi trường | AWS Cost Explorer lọc theo `Project`, `Environment`, `CostCenter` |
| Dễ tìm resource khi hệ thống lớn dần | Naming pattern nhất quán giúp search trong Console/CLI nhanh |
| Tránh xóa nhầm resource | Tag `ManagedBy=Terraform` giúp phân biệt resource nào được quản lý bằng code, resource nào tạo tay để test (không nên tồn tại lâu dài) |
| Hỗ trợ IAM Condition nâng cao | Có thể viết policy dạng "chỉ cho phép thao tác trên resource có tag `Environment=dev`" — hữu ích nếu sau này mở rộng nhiều người cùng thao tác |
| Alert đúng người khi có sự cố | Tag `Owner` giúp xác định nhanh ai chịu trách nhiệm resource gặp vấn đề |

---

## 6. Checklist áp dụng khi code Terraform

- [ ] `default_tags` đã cấu hình ở mọi `provider "aws"` block của từng environment
- [ ] Biến `owner` được truyền vào qua `terraform.tfvars` của từng environment, không hardcode
- [ ] Mọi resource tuân theo naming pattern đã liệt kê ở mục 2.2 — nên review lại tên resource trước khi `terraform apply` lần đầu
- [ ] S3 bucket name đã kiểm tra tính khả dụng (globally unique) trước khi apply, tránh lỗi tên bị trùng giữa chừng
- [ ] Resource có dữ liệu nhạy cảm (RDS, Secrets Manager) đã gắn tag `DataClassification=confidential`

---

## 7. Việc cần làm tiếp theo

Sau khi chốt Naming Convention & Tagging Standard, bước tiếp theo trong giai đoạn thiết kế là **CI/CD Design** (`docs/cicd-pipeline.md`) — mô tả chi tiết sơ đồ pipeline, điều kiện trigger từng bước, và chiến lược rollback, dựa trên cấu trúc ECR/ECS đã đặt tên chuẩn ở tài liệu này.

