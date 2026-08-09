# MatchLens

<p align="center">
  <img src="https://img.shields.io/badge/TypeScript-007ACC?style=for-the-badge&logo=typescript&logoColor=white" />
  <img src="https://img.shields.io/badge/NestJS-E0234E?style=for-the-badge&logo=nestjs&logoColor=white" />
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" />
  <img src="https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white" />
  <img src="https://img.shields.io/badge/Prisma-2D3748?style=for-the-badge&logo=prisma&logoColor=white" />
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" />
  <img src="https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white" />
  <img src="https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white" />
  <img src="https://img.shields.io/badge/GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white" />
</p>

> A football match analytics platform: automatic highlight extraction using AI (YOLOv11) and player metrics analysis, helping coaches prepare tactics for their next matches.

## 📖 Introduction

MatchLens empowers amateur and grassroots football teams—who lack the budget for professional analysis software—to upload match videos, automatically receive highlight clips, and view comprehensive player movement reports (heatmaps, distance covered, sprint speeds).

This is a personal project built with a strong emphasis on **production-grade AWS infrastructure**: Infrastructure as Code (IaC), least-privilege security principles, automated CI/CD, observability, and disaster recovery (DR) capabilities—moving far beyond a simple functional application.

## 🏛️ Architecture

For a detailed view, see [`docs/architecture.md`](docs/architecture.md).

**Overview:** Videos are uploaded directly to S3 via presigned URLs, triggering an asynchronous processing pipeline (SQS → ECS Fargate Worker running YOLOv11) to extract highlights and tracking data. The tracking data is then processed via AWS Glue to calculate player metrics, queried via Athena, and displayed on the dashboard.

## 💻 Tech Stack

- **Backend:** NestJS (Node.js 22 + pnpm + Prisma 7.9), running on Amazon ECS Fargate
- **AI/CV:** YOLOv11 (object detection) + ByteTrack/BoT-SORT (multi-object tracking) + OpenCV (homography)
- **Database:** PostgreSQL (RDS Multi-AZ + Read Replica), Amazon DynamoDB
- **Storage:** Amazon S3 (Data Lake architecture: raw → processed → curated)
- **Serverless:** AWS Lambda (job dispatcher, status updater, MediaConvert trigger)
- **IaC:** Terraform (8 modules, 3 environments)
- **CI/CD:** GitHub Actions (OIDC) + Amazon ECR + Trivy
- **Data & Analytics:** AWS Glue, Amazon Athena
- **Observability:** Amazon CloudWatch, SNS, AWS Budgets

## ⚠️ Known Limitations (Current Version)

These are **intentional** simplifications to maintain focus on the core infrastructure, not accidental omissions:

| Limitation | Details | Future Extension |
|---|---|---|
| **Static Camera Only** | Pixel-to-pitch coordinate conversion uses homography with 4 pre-configured reference points, requiring a fixed tactical camera. Cannot process broadcast footage (pan/zoom cameras). | Dynamic camera calibration per frame. |
| **No Jersey Number Recognition** | AI does not perform OCR on jersey numbers. The tracker generates persistent `track_ids` (Track #1, #2...) for a match; coaches manually map `track_id → player` via the UI. | OCR jersey recognition or re-identification models. |
| **No Malware Scanning on Uploads** | Currently only validates content-type and file size when issuing presigned URLs. | ClamAV on Lambda, or GuardDuty Malware Protection for S3. |
| **Single Match Scope** | No feature yet for aggregating data across multiple matches or an entire season. | Expansion after the core pipeline stabilizes. |

## 📚 Design Documentation

The entire design process prior to implementation is documented in the [`docs/`](docs/) directory:

- **[⭐ Architectural Decision Record (ADR)](docs/decision-record.md)** — The source of truth: 39 finalized architectural decisions with rationale and trade-offs.
- [Infrastructure Architecture](docs/architecture.md)
- [Deployment Roadmap](docs/roadmap.md)
- [Backend Architecture](docs/backend-architecture.md)
- [Database Schema & ERD](docs/database-schema.md)
- [Data Contracts (AI & Glue)](docs/data-contracts.md)
- [System Flows](docs/system-flows.md)
- [Data Model & S3 Strategy](docs/data-model.md)
- [API Design](docs/api-design.md)
- [IAM & Security Design](docs/iam-security-design.md)
- [Terraform Module Structure](docs/terraform-structure.md)
- [Naming & Tagging Standard](docs/naming-tagging-standard.md)
- [CI/CD Design](docs/cicd-design.md)
- [Cost Estimate](docs/cost-estimate.md)

## 🚀 Project Status

The Design Phase is complete, with all architectural decisions finalized. Currently executing **Phase 0** (application foundation + core infrastructure). See detailed progress per phase in [`docs/roadmap.md`](docs/roadmap.md).

## 📄 License

This is a personal project intended for learning purposes and portfolio showcasing.
