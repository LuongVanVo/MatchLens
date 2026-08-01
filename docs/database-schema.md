# MatchLens — Database Schema Chi Tiết (ERD / Entity Design)

> Đặc tả kỹ thuật đầy đủ cho RDS PostgreSQL, dùng trực tiếp để sinh Prisma Schema và migration trong Backend NestJS. Mở rộng chi tiết từ `docs/data-model.md` mục 1.

---

## 1. Sơ đồ quan hệ (ERD)

```
┌──────────────┐         ┌──────────────┐
│    users      │         │    teams      │
├──────────────┤ 1     N ├──────────────┤
│ id (PK)       │────────│ id (PK)       │
│ email         │         │ owner_id (FK) │
│ password_hash │         │ name          │
│ full_name     │         │ created_at    │
│ role          │         └───────┬──────┘
│ created_at    │                 │ 1
│ updated_at    │                 │
│ deleted_at    │                 │ N
└──────────────┘         ┌───────▼──────┐       ┌───────────────┐
                          │   players     │       │    matches     │
                          ├──────────────┤       ├───────────────┤
                          │ id (PK)       │       │ id (PK)        │
                          │ team_id (FK)  │       │ team_id (FK)   │
                          │ full_name     │       │ opponent_name  │
                          │ jersey_number │       │ match_date     │
                          │ position      │       │ video_s3_key   │
                          │ created_at    │       │ status (enum)  │
                          │ updated_at    │       │ duration_sec   │
                          │ deleted_at    │       │ created_at     │
                          └──────────────┘       │ updated_at     │
                                                   │ deleted_at     │
                                                   └───────────────┘
```

---

## 2. Chi tiết từng bảng (đặc tả cột đầy đủ)

### 2.1. Bảng `users`

| Cột | Kiểu dữ liệu | Ràng buộc | Ghi chú |
|---|---|---|---|
| `id` | `UUID` | PK, `DEFAULT gen_random_uuid()` | |
| `email` | `VARCHAR(255)` | `NOT NULL`, `UNIQUE` | Dùng đăng nhập |
| `password_hash` | `VARCHAR(255)` | `NOT NULL` | Hash bằng bcrypt, cost factor 10-12 |
| `full_name` | `VARCHAR(255)` | `NOT NULL` | |
| `role` | `VARCHAR(50)` | `NOT NULL`, `DEFAULT 'coach'`, `CHECK (role IN ('coach', 'admin'))` | |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |
| `updated_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | Tự động update qua trigger hoặc Prisma `@updatedAt` |
| `deleted_at` | `TIMESTAMPTZ` | `NULL` | Soft-delete, `NULL` = chưa xóa |

**Index:** `UNIQUE INDEX idx_users_email ON users(email)`

---

### 2.2. Bảng `teams`

| Cột | Kiểu dữ liệu | Ràng buộc | Ghi chú |
|---|---|---|---|
| `id` | `UUID` | PK, `DEFAULT gen_random_uuid()` | |
| `owner_id` | `UUID` | `NOT NULL`, FK → `users.id` `ON DELETE RESTRICT` | Không cho xóa user nếu còn team sở hữu |
| `name` | `VARCHAR(255)` | `NOT NULL` | |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |
| `updated_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |
| `deleted_at` | `TIMESTAMPTZ` | `NULL` | Soft-delete |

**Index:** `INDEX idx_teams_owner_id ON teams(owner_id)`

---

### 2.3. Bảng `players`

| Cột | Kiểu dữ liệu | Ràng buộc | Ghi chú |
|---|---|---|---|
| `id` | `UUID` | PK, `DEFAULT gen_random_uuid()` | |
| `team_id` | `UUID` | `NOT NULL`, FK → `teams.id` `ON DELETE CASCADE` | Xóa team thì xóa luôn player |
| `full_name` | `VARCHAR(255)` | `NOT NULL` | |
| `jersey_number` | `SMALLINT` | `NULL`, `CHECK (jersey_number BETWEEN 1 AND 99)` | |
| `position` | `VARCHAR(50)` | `NULL`, `CHECK (position IN ('goalkeeper','defender','midfielder','forward'))` | |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |
| `updated_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |
| `deleted_at` | `TIMESTAMPTZ` | `NULL` | Soft-delete |

**Index:** `INDEX idx_players_team_id ON players(team_id)`
**Ràng buộc bổ sung:** `UNIQUE INDEX idx_players_team_jersey ON players(team_id, jersey_number) WHERE deleted_at IS NULL` — không cho 2 cầu thủ cùng đội trùng số áo (chỉ áp dụng với player chưa xóa)

---

### 2.4. Bảng `matches`

| Cột | Kiểu dữ liệu | Ràng buộc | Ghi chú |
|---|---|---|---|
| `id` | `UUID` | PK, `DEFAULT gen_random_uuid()` | |
| `team_id` | `UUID` | `NOT NULL`, FK → `teams.id` `ON DELETE CASCADE` | |
| `opponent_name` | `VARCHAR(255)` | `NOT NULL` | Dạng text tự do |
| `match_date` | `DATE` | `NOT NULL` | |
| `video_s3_key` | `VARCHAR(512)` | `NULL` | `NULL` cho tới khi upload xong |
| `duration_sec` | `INTEGER` | `NULL` | Độ dài video, ghi nhận sau khi worker xử lý xong |
| `status` | `VARCHAR(50)` | `NOT NULL`, `DEFAULT 'pending'`, `CHECK (status IN ('pending','uploaded','processing','completed','failed'))` | Xem transition ở mục 3 |
| `error_message` | `TEXT` | `NULL` | Ghi lại lý do nếu `status = 'failed'` |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |
| `updated_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |
| `deleted_at` | `TIMESTAMPTZ` | `NULL` | Soft-delete |

**Index:**
- `INDEX idx_matches_team_id ON matches(team_id)`
- `INDEX idx_matches_status ON matches(status)` — phục vụ query "tất cả match đang processing" (dùng cho job giám sát/dashboard)

**Lưu ý quan trọng:** cột `status` ở đây có 5 giá trị (`pending`, `uploaded`, `processing`, `completed`, `failed`) — chi tiết hơn so với 4 giá trị (`pending`, `processing`, `completed`, `failed`) đã liệt kê sơ bộ ở `api-design.md` mục "processing_status". Bổ sung `uploaded` để phân biệt rõ 2 mốc: (a) đã tạo match nhưng chưa upload video xong (`pending`), và (b) đã upload xong, đang chờ S3 Event kích hoạt worker (`uploaded`), tránh nhầm lẫn giữa "chưa có video" và "có video nhưng chưa xử lý".

---

## 3. State Machine của `matches.status`

```
pending ──(upload video thành công, confirm-upload)──> uploaded
uploaded ──(S3 Event trigger Lambda thành công, job vào SQS)──> processing
processing ──(Worker xử lý xong, ghi kết quả)──> completed
processing ──(Worker fail sau max retry, vào DLQ)──> failed
```

**Quy tắc:** Backend chỉ được set `status` qua các transition hợp lệ ở trên — không cho phép nhảy trạng thái tùy ý (ví dụ không thể set thẳng từ `pending` sang `completed`). Nên implement validate transition này ở tầng service (NestJS), không chỉ dựa vào CHECK constraint của DB.

---

## 4. Chuẩn Prisma Schema tương ứng (tham chiếu để code)

```prisma
// schema.prisma (rút gọn, minh họa cấu trúc — code thật cần đầy đủ hơn)

model User {
  id           String    @id @default(uuid()) @db.Uuid
  email        String    @unique @db.VarChar(255)
  passwordHash String    @map("password_hash") @db.VarChar(255)
  fullName     String    @map("full_name") @db.VarChar(255)
  role         String    @default("coach") @db.VarChar(50)
  createdAt    DateTime  @default(now()) @map("created_at") @db.Timestamptz
  updatedAt    DateTime  @updatedAt @map("updated_at") @db.Timestamptz
  deletedAt    DateTime? @map("deleted_at") @db.Timestamptz
  teams        Team[]

  @@map("users")
}

model Team {
  id        String    @id @default(uuid()) @db.Uuid
  ownerId   String    @map("owner_id") @db.Uuid
  owner     User      @relation(fields: [ownerId], references: [id])
  name      String    @db.VarChar(255)
  createdAt DateTime  @default(now()) @map("created_at") @db.Timestamptz
  updatedAt DateTime  @updatedAt @map("updated_at") @db.Timestamptz
  deletedAt DateTime? @map("deleted_at") @db.Timestamptz
  players   Player[]
  matches   Match[]

  @@index([ownerId])
  @@map("teams")
}

model Match {
  id           String    @id @default(uuid()) @db.Uuid
  teamId       String    @map("team_id") @db.Uuid
  team         Team      @relation(fields: [teamId], references: [id], onDelete: Cascade)
  opponentName String    @map("opponent_name") @db.VarChar(255)
  matchDate    DateTime  @map("match_date") @db.Date
  videoS3Key   String?   @map("video_s3_key") @db.VarChar(512)
  durationSec  Int?      @map("duration_sec")
  status       String    @default("pending") @db.VarChar(50)
  errorMessage String?   @map("error_message")
  createdAt    DateTime  @default(now()) @map("created_at") @db.Timestamptz
  updatedAt    DateTime  @updatedAt @map("updated_at") @db.Timestamptz
  deletedAt    DateTime? @map("deleted_at") @db.Timestamptz

  @@index([teamId])
  @@index([status])
  @@map("matches")
}

model Player {
  id            String    @id @default(uuid()) @db.Uuid
  teamId        String    @map("team_id") @db.Uuid
  team          Team      @relation(fields: [teamId], references: [id], onDelete: Cascade)
  fullName      String    @map("full_name") @db.VarChar(255)
  jerseyNumber  Int?      @map("jersey_number") @db.SmallInt
  position      String?   @db.VarChar(50)
  createdAt     DateTime  @default(now()) @map("created_at") @db.Timestamptz
  updatedAt     DateTime  @updatedAt @map("updated_at") @db.Timestamptz
  deletedAt     DateTime? @map("deleted_at") @db.Timestamptz

  @@index([teamId])
  @@map("players")
}
```

**Ghi chú:** CHECK constraint cho `role`, `status`, `position` (enum dạng string) không thể khai báo trực tiếp qua Prisma schema thông thường — cần thêm qua raw SQL migration (`ALTER TABLE ... ADD CONSTRAINT ...`) sau khi Prisma generate migration ban đầu, hoặc dùng Prisma `enum` thay vì `String` nếu muốn Prisma tự quản lý (khuyến nghị dùng `enum` của Prisma cho `status` vì đây là giá trị cố định, dùng `String` cho `role`/`position` nếu muốn linh hoạt mở rộng sau này).

---

## 5. Việc cần làm tiếp theo

Sau khi có Database Schema chi tiết này, kết hợp với `docs/data-contracts.md` (schema DynamoDB + S3 JSON) và `docs/backend-architecture.md` (cấu trúc NestJS), Backend đã đủ đặc tả để bắt đầu code Entity/Migration ngay từ Phase 0.

