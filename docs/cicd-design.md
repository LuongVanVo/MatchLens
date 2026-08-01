# MatchLens — CI/CD Design

> Thiết kế chi tiết pipeline CI/CD, dựa trên IAM & Security Design (OIDC role đã định nghĩa) và Naming Convention (ECR repo, ECS service đã đặt tên chuẩn). Áp dụng cho cả Backend API Service và AI Worker Service.

---

## 1. Nguyên tắc thiết kế chung

- Build 1 lần, promote nhiều môi trường (build once, promote everywhere) — không build lại image riêng cho từng environment, tránh sai lệch giữa các môi trường do build khác thời điểm
- Mọi image trước khi deploy đều phải qua bước quét lỗ hổng bảo mật (Trivy) — pipeline dừng ngay nếu phát hiện lỗ hổng mức nghiêm trọng (Critical/High tùy ngưỡng cấu hình)
- Xác thực với AWS qua OIDC Federation, không dùng access key/secret key tĩnh lưu trong GitHub Secrets (đã nêu ở IAM & Security Design mục 3.5)
- Production luôn yêu cầu approval thủ công — không có ngoại lệ, kể cả khi pipeline dev/staging đã pass hoàn toàn
- Rollback phải thực hiện được nhanh chóng bằng cách revert về ECS Task Definition version trước đó, không cần build lại image

---

## 2. Chiến lược nhánh Git (Branching Strategy)

| Nhánh | Mục đích | Môi trường tự động deploy |
|---|---|---|
| `feature/*` | Nhánh phát triển tính năng | Không tự động deploy, chỉ chạy test/lint |
| `develop` | Nhánh tích hợp, code đã review | `dev` |
| `main` | Code ổn định, sẵn sàng release | `staging` (tự động) → `prod` (cần approval) |
| `hotfix/*` | Sửa lỗi khẩn cấp từ `main` | Theo luồng riêng, có thể bỏ qua `dev`/`staging` nếu cực kỳ khẩn cấp (cần ghi log rõ lý do) |

**Quy trình:**
1. Developer tạo `feature/xxx` từ `develop`, code xong mở PR vào `develop`
2. PR yêu cầu: pass lint, pass unit test, ít nhất 1 approval review (nếu làm nhóm; nếu làm solo, tự review kỹ trước khi merge)
3. Merge vào `develop` → tự động deploy `dev`
4. Khi đủ tính năng cho 1 đợt release, mở PR từ `develop` vào `main`
5. Merge vào `main` → tự động deploy `staging`, sau đó chờ approval để deploy `prod`

---

## 3. Sơ đồ pipeline tổng thể

```
[Push code / Merge PR]
        │
        ▼
┌───────────────────┐
│   Lint & Test       │  (flake8/eslint, pytest/jest)
└─────────┬──────────┘
          │ pass
          ▼
┌───────────────────┐
│  Build Docker Image │  (Backend + Worker, build song song)
└─────────┬──────────┘
          │
          ▼
┌───────────────────┐
│  Trivy Image Scan   │  → FAIL nếu có lỗ hổng Critical/High
└─────────┬──────────┘
          │ pass
          ▼
┌───────────────────┐
│  Push to Amazon ECR │  (tag theo git SHA + tag môi trường)
└─────────┬──────────┘
          │
          ▼
   ┌──────┴───────┐
   │  Nhánh nào?    │
   └──────┬───────┘
          │
   ┌──────┼───────────────┬─────────────────────┐
   ▼                       ▼                     ▼
develop                  main                 hotfix/*
   │                       │                      │
   ▼                       ▼                      ▼
Deploy dev            Deploy staging         (theo luồng riêng)
(tự động)              (tự động)
                           │
                           ▼
                   [Manual Approval Gate]
                           │
                           ▼
                     Deploy prod
```

---

## 4. Chi tiết từng bước trong GitHub Actions Workflow

### 4.1. Job: `lint-and-test`
- Chạy static analysis (flake8/black cho Python nếu Backend dùng NestJS, eslint nếu dùng Node.js)
- Chạy unit test cho cả Backend API và AI Worker (mock các dependency AWS như S3/SQS khi test, không gọi AWS thật)
- Điều kiện: chạy trên mọi PR và push, không phân biệt nhánh

### 4.2. Job: `build-and-scan`
- Phụ thuộc (`needs`) vào `lint-and-test` pass trước
- Build Docker image riêng cho Backend và Worker (2 job song song hoặc matrix strategy)
- Tag image: `{ecr-repo}:{git-sha}` — luôn dùng git SHA làm tag chính để đảm bảo truy vết được chính xác version nào đang chạy
- Chạy Trivy scan trên image vừa build, output báo cáo dưới dạng SARIF để hiển thị trong tab Security của GitHub (nếu dùng GitHub Advanced Security) hoặc đơn giản là fail step nếu có finding mức Critical/High

### 4.3. Job: `push-to-ecr`
- Chỉ chạy nếu `build-and-scan` pass hoàn toàn
- Xác thực AWS qua OIDC (dùng `aws-actions/configure-aws-credentials` với `role-to-assume` trỏ tới `matchlens-{env}-cicd-role`)
- Push image lên ECR repository tương ứng (`matchlens-backend`, `matchlens-worker`)

### 4.4. Job: `deploy-dev` (điều kiện: nhánh `develop`)
- Cập nhật ECS Task Definition với image tag mới (git SHA)
- Gọi `aws ecs update-service --force-new-deployment` cho cả `matchlens-dev-backend-service` và `matchlens-dev-worker-service`
- Chờ ECS service ổn định (`aws ecs wait services-stable`) trước khi coi bước deploy là thành công

### 4.5. Job: `deploy-staging` (điều kiện: nhánh `main`)
- Tương tự `deploy-dev` nhưng trỏ tới resource `staging`
- Tự động chạy, không cần approval (vì staging dùng để kiểm thử trước khi lên prod, không phải môi trường người dùng thật)

### 4.6. Job: `deploy-prod` (điều kiện: nhánh `main`, sau khi `deploy-staging` pass)
- Dùng **GitHub Environment Protection Rule** (`environment: production` trong workflow) — yêu cầu 1 người có quyền approve trước khi job này chạy tiếp
- Sau khi được approve, thực hiện deploy tương tự các bước trên nhưng trỏ tới resource `prod`
- Ghi log rõ ràng: ai approve, thời điểm approve, image tag nào được deploy — phục vụ audit trail

---

## 5. Chiến lược Rollback

| Tình huống | Cách xử lý |
|---|---|
| Phát hiện lỗi ngay sau khi deploy prod | Chạy lệnh `aws ecs update-service` trỏ về **Task Definition revision trước đó** (ECS tự lưu lịch sử các revision, không cần build lại image) |
| Lỗi nghiêm trọng, cần rollback khẩn cấp | Chuẩn bị sẵn 1 GitHub Actions workflow riêng (`rollback.yml`) có thể trigger thủ công (`workflow_dispatch`), nhận input là Task Definition revision muốn rollback về |
| Lỗi do dữ liệu (migration sai) | Không thuộc phạm vi rollback qua CI/CD — cần quy trình riêng liên quan tới RDS (xem thêm phần Disaster Recovery trong System Flows) |

**Lưu ý quan trọng:** vì dùng chiến lược "build once, tag theo git SHA", việc rollback ECS Service về revision cũ **không cần build lại**, chỉ cần trỏ lại Task Definition — đây là lý do quan trọng của việc tag theo git SHA thay vì tag `latest`.

---

## 6. Deployment Strategy (cách ECS cập nhật service)

- Dùng **Rolling Update** mặc định của ECS (không cần Blue/Green phức tạp ở giai đoạn đầu dự án, vì quy mô nhỏ)
- Cấu hình `minimumHealthyPercent` và `maximumPercent` hợp lý (ví dụ 50%/200%) để đảm bảo luôn có ít nhất 1 task chạy trong lúc update, tránh downtime
- Ghi chú mở rộng sau này: nếu muốn nâng cấp lên Blue/Green thực sự, có thể tích hợp **AWS CodeDeploy** cho ECS — nhưng đây là điểm để dành cho giai đoạn mở rộng, không bắt buộc ở bản đầu

---

## 7. Secrets & Credentials trong Pipeline

| Loại | Cách quản lý |
|---|---|
| AWS credentials | Không lưu access key — dùng OIDC Federation (đã thiết kế ở IAM & Security Design) |
| Docker registry credentials | Không cần, vì `aws-actions/amazon-ecr-login` action tự lấy token qua IAM Role đang assume |
| Slack/Email webhook (thông báo kết quả pipeline) | Lưu trong GitHub Secrets riêng biệt (`SLACK_WEBHOOK_URL`), không liên quan AWS nên chấp nhận lưu dạng secret thông thường của GitHub |

---

## 8. Thông báo kết quả Pipeline

- Sau mỗi lần deploy (dev/staging/prod), gửi thông báo về Slack/Email: trạng thái (thành công/thất bại), git SHA, người trigger, thời gian
- Riêng bước `deploy-prod`: thông báo kèm rõ ai đã approve, để tăng tính minh bạch trong audit trail

---

## 9. Bảng tổng hợp Job & Điều kiện Trigger

| Job | Trigger | Môi trường đích | Cần approval |
|---|---|---|---|
| lint-and-test | Mọi push/PR | — | Không |
| build-and-scan | Sau lint-and-test pass | — | Không |
| push-to-ecr | Sau build-and-scan pass | — | Không |
| deploy-dev | Push/merge vào `develop` | dev | Không |
| deploy-staging | Push/merge vào `main` | staging | Không |
| deploy-prod | Sau deploy-staging pass | prod | **Có** |
| rollback (manual) | `workflow_dispatch` thủ công | Chọn khi trigger | Tùy cấu hình, khuyến nghị vẫn cần approval cho prod |

---

## 10. Câu hỏi còn mở — cần quyết định trước khi code

- [ ] Có cần chạy integration test (gọi thật API sau khi deploy dev) tự động trong pipeline không, hay chỉ dừng ở unit test?
- [ ] Ngưỡng Trivy fail cụ thể là gì — chỉ Critical, hay cả High? Cần cân bằng giữa an toàn và tránh block pipeline quá thường xuyên vì lỗ hổng nhỏ trong base image
- [ ] Ai là người có quyền approve deploy prod trong GitHub Environment Protection Rule? (với dự án cá nhân, đây có thể là chính bạn, nhưng vẫn nên cấu hình đúng quy trình để thể hiện hiểu biết chuẩn doanh nghiệp)
- [ ] Có cần thêm bước smoke test tự động ngay sau khi deploy prod xong (gọi thử 1-2 endpoint quan trọng) trước khi coi deploy là hoàn tất không?

---

## 11. Việc cần làm tiếp theo

Sau khi chốt CI/CD Design, bước cuối cùng trong giai đoạn thiết kế là **Cost Estimate** (`docs/cost-estimate.md`) — ước tính chi phí AWS theo từng service chính, thiết lập ngưỡng Budget Alert trước khi bắt đầu deploy thật, để tránh phát sinh chi phí ngoài kiểm soát trong quá trình phát triển và demo.

