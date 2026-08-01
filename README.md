# MatchLens

> Nền tảng phân tích trận đấu bóng đá: tự động cắt highlight bằng AI (YOLOv11) và phân tích chỉ số cầu thủ, giúp huấn luyện viên chuẩn bị chiến thuật cho trận tiếp theo.

## Giới thiệu

MatchLens giúp các đội bóng phong trào/nghiệp dư — vốn không có ngân sách cho phần mềm phân tích chuyên nghiệp — có thể upload video trận đấu, tự động nhận được các đoạn highlight, và xem báo cáo chỉ số vận động của cầu thủ (heatmap, quãng đường di chuyển, tốc độ).

Đây là dự án cá nhân được xây dựng với trọng tâm là **hạ tầng AWS chuẩn production**: Infrastructure as Code, bảo mật theo nguyên tắc least-privilege, CI/CD tự động, giám sát/observability, và khả năng phục hồi sau sự cố (DR) — không chỉ đơn thuần là một ứng dụng chạy được.

## Kiến trúc

Xem chi tiết tại [`docs/architecture.md`](docs/architecture.md).

Tổng quan: Video được upload trực tiếp lên S3 qua presigned URL, kích hoạt pipeline xử lý bất đồng bộ (SQS → ECS Fargate Worker chạy YOLOv11) để cắt highlight và trích xuất dữ liệu tracking. Dữ liệu tracking sau đó được xử lý qua AWS Glue để tính toán chỉ số cầu thủ, truy vấn qua Athena và hiển thị qua QuickSight.

## Tech Stack

- **Backend:** NestJS (với pnpm), chạy trên ECS Fargate
- **AI:** YOLOv11 (object detection cho cầu thủ, bóng, sự kiện)
- **Database:** PostgreSQL (RDS), DynamoDB
- **Storage:** S3 (data lake: raw → processed → curated)
- **IaC:** Terraform
- **CI/CD:** GitHub Actions + Amazon ECR + Trivy
- **Data & Analytics:** AWS Glue, Athena, QuickSight
- **Observability:** CloudWatch, SNS

## Tài liệu thiết kế

Toàn bộ quá trình thiết kế trước khi triển khai được lưu tại [`docs/`](docs/):

- [Kiến trúc hạ tầng (Infrastructure Architecture)](docs/architecture.md)
- [Roadmap triển khai chi tiết (Deployment Roadmap)](docs/roadmap.md)
- [Kiến trúc Backend NestJS (Backend Architecture)](docs/backend-architecture.md)
- [Cấu trúc Database & ERD (Database Schema)](docs/database-schema.md)
- [Thỏa thuận Dữ liệu I/O (Data Contracts - AI & Glue)](docs/data-contracts.md)
- [Luồng hệ thống (System Flows)](docs/system-flows.md)
- [Data Model & S3 Strategy](docs/data-model.md)
- [API Design](docs/api-design.md)
- [IAM & Security Design](docs/iam-security-design.md)
- [Terraform Module Structure](docs/terraform-structure.md)
- [Naming & Tagging Standard](docs/naming-tagging-standard.md)
- [CI/CD Design](docs/cicd-design.md)
- [Cost Estimate](docs/cost-estimate.md)

## Trạng thái dự án

Đang trong giai đoạn triển khai. Xem tiến độ chi tiết theo từng Phase tại [`CLAUDE.md`](CLAUDE.md) mục 5.

## Giấy phép

Dự án cá nhân, phục vụ mục đích học tập và portfolio.

