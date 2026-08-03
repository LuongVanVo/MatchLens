# MatchLens

> Nền tảng phân tích trận đấu bóng đá: tự động cắt highlight bằng AI (YOLOv11) và phân tích chỉ số cầu thủ, giúp huấn luyện viên chuẩn bị chiến thuật cho trận tiếp theo.

## Giới thiệu

MatchLens giúp các đội bóng phong trào/nghiệp dư — vốn không có ngân sách cho phần mềm phân tích chuyên nghiệp — có thể upload video trận đấu, tự động nhận được các đoạn highlight, và xem báo cáo chỉ số vận động của cầu thủ (heatmap, quãng đường di chuyển, tốc độ).

Đây là dự án cá nhân được xây dựng với trọng tâm là **hạ tầng AWS chuẩn production**: Infrastructure as Code, bảo mật theo nguyên tắc least-privilege, CI/CD tự động, giám sát/observability, và khả năng phục hồi sau sự cố (DR) — không chỉ đơn thuần là một ứng dụng chạy được.

## Kiến trúc

Xem chi tiết tại [`docs/architecture.md`](docs/architecture.md).

Tổng quan: Video được upload trực tiếp lên S3 qua presigned URL, kích hoạt pipeline xử lý bất đồng bộ (SQS → ECS Fargate Worker chạy YOLOv11) để cắt highlight và trích xuất dữ liệu tracking. Dữ liệu tracking sau đó được xử lý qua AWS Glue để tính toán chỉ số cầu thủ, truy vấn qua Athena và hiển thị trên dashboard.

## Tech Stack

- **Backend:** NestJS (Node 22 + pnpm + Prisma 6), chạy trên ECS Fargate
- **AI:** YOLOv11 (object detection) + ByteTrack/BoT-SORT (multi-object tracking) + OpenCV (homography)
- **Database:** PostgreSQL (RDS Multi-AZ + Read Replica), DynamoDB
- **Storage:** S3 (data lake: raw → processed → curated)
- **Serverless:** Lambda (job dispatcher, status updater, MediaConvert trigger)
- **IaC:** Terraform (8 module, 3 environment)
- **CI/CD:** GitHub Actions (OIDC) + Amazon ECR + Trivy
- **Data & Analytics:** AWS Glue, Athena
- **Observability:** CloudWatch, SNS, AWS Budget

## Giới hạn đã biết của phiên bản hiện tại

Đây là các đơn giản hóa **có chủ đích** để tập trung vào phần hạ tầng — không phải thiếu sót do bỏ qua:

| Giới hạn | Chi tiết | Hướng mở rộng |
|---|---|---|
| **Camera tĩnh** | Việc quy đổi tọa độ pixel → tọa độ sân dùng homography với 4 điểm mốc cấu hình trước, nên chỉ hoạt động với camera chiến thuật đặt cố định. Không xử lý được footage truyền hình (camera pan/zoom) | Camera calibration động theo từng frame |
| **Không nhận diện số áo** | AI không OCR số áo. Tracker sinh `track_id` (Track #1, #2...) bền vững trong 1 trận; huấn luyện viên gán thủ công `track_id → cầu thủ` qua giao diện | OCR số áo hoặc re-identification model |
| **Chưa quét virus file upload** | Hiện chỉ validate content-type và kích thước file khi cấp presigned URL | ClamAV trên Lambda, hoặc GuardDuty Malware Protection for S3 |
| **Phạm vi 1 trận đấu** | Chưa có tính năng tổng hợp nhiều trận / cả mùa giải | Mở rộng sau khi phần lõi ổn định |

## Tài liệu thiết kế

Toàn bộ quá trình thiết kế trước khi triển khai được lưu tại [`docs/`](docs/):

- **[⭐ Architectural Decision Record (ADR)](docs/decision-record.md)** — nguồn chân lý: 39 quyết định kiến trúc đã chốt kèm lý do và đánh đổi
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

Design Phase hoàn thành, đã chốt toàn bộ quyết định kiến trúc. Đang bắt đầu Phase 0 (nền tảng ứng dụng + hạ tầng cơ bản). Xem tiến độ chi tiết theo từng Phase tại [`docs/roadmap.md`](docs/roadmap.md).

## Giấy phép

Dự án cá nhân, phục vụ mục đích học tập và portfolio.

