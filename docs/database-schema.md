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
└──────┬───────┘         ┌───────▼──────┐       ┌───────────────┐
       │ 1                │   players     │       │    matches     │
       │                  ├──────────────┤       ├───────────────┤
       │ N                │ id (PK)       │       │ id (PK)        │
┌──────▼────────┐        │ team_id (FK)  │       │ team_id (FK)   │
│ refresh_tokens│        │ full_name     │       │ opponent_name  │
├───────────────┤        │ jersey_number │       │ match_date     │
│ id (PK)        │        │ position      │       │ video_s3_key   │
│ user_id (FK)   │        │ created_at    │       │ status (enum)  │
│ token_hash     │        │ updated_at    │       │ error_message  │
│ expires_at     │        │ deleted_at    │       │ duration_sec   │
│ revoked_at     │        └──────┬───────┘       │ created_at     │
│ created_at     │               │ 0..1          │ updated_at     │
└───────────────┘               │               │ deleted_at     │
                                 │               └───────┬───────┘
                                 │                       │ 1
                                 │  N                    │ N
                          ┌──────▼───────────────────────▼──────┐
                          │      match_track_mappings            │
                          ├──────────────────────────────────────┤
                          │ id (PK)                              │
                          │ match_id (FK → matches.id)           │
                          │ track_id (INT, do tracker sinh)      │
                          │ player_id (FK → players.id, NULL)    │
                          │ team_side ('home'/'away')            │
                          │ created_at / updated_at              │
                          │ UNIQUE (match_id, track_id)          │
                          └──────────────────────────────────────┘
```

**2 bảng mới so với thiết kế ban đầu:**
- `refresh_tokens` — cho phép revoke token khi logout (quyết định Q12)
- `match_track_mappings` — lưu mapping `track_id → player_id` do HLV gán thủ công, vì v1 không OCR số áo (quyết định Q25, D1)

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

**Lưu ý quan trọng:** cột `status` có **5 giá trị** (`pending`, `uploaded`, `processing`, `completed`, `failed`). Giá trị `uploaded` phân biệt rõ 2 mốc: (a) đã tạo match nhưng chưa upload video xong (`pending`), và (b) đã upload xong, đang chờ S3 Event kích hoạt worker (`uploaded`) — tránh nhầm lẫn giữa "chưa có video" và "có video nhưng chưa xử lý".

**Tên cột vs tên field API** (quyết định Q10): cột DB tên `status`, API request/response DTO dùng key `processing_status`. Cả 2 tầng đồng bộ đúng 5 giá trị trên. `api-design.md` đã được cập nhật để bao gồm `uploaded`.

---

### 2.5. Bảng `refresh_tokens` (quyết định Q12)

Cho phép `POST /v1/auth/logout` revoke được refresh token — nếu không có bảng này, JWT stateless không thể vô hiệu hóa trước khi hết hạn.

| Cột | Kiểu dữ liệu | Ràng buộc | Ghi chú |
|---|---|---|---|
| `id` | `UUID` | PK, `DEFAULT gen_random_uuid()` | |
| `user_id` | `UUID` | `NOT NULL`, FK → `users.id` `ON DELETE CASCADE` | Xóa user thì xóa luôn token |
| `token_hash` | `VARCHAR(255)` | `NOT NULL` | **Hash của token (SHA-256), không lưu token thô** — nếu DB bị lộ, attacker không dùng được token |
| `expires_at` | `TIMESTAMPTZ` | `NOT NULL` | Thời điểm token hết hạn (7 ngày sau khi cấp) |
| `revoked_at` | `TIMESTAMPTZ` | `NULL` | `NULL` = còn hiệu lực; có giá trị = đã logout |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |

**Index:**
- `INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id)`
- `UNIQUE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash)` — phục vụ tra cứu nhanh khi verify

**Quy tắc dọn dẹp:** nên có job định kỳ (hoặc query khi login) xóa các row có `expires_at < now()` để bảng không phình vô hạn.

---

### 2.6. Bảng `match_track_mappings` (quyết định Q25, D1)

Vì v1 **không nhận diện số áo** (không OCR), tracker chỉ sinh ra `track_id` là số nguyên tạm thời trong phạm vi 1 trận. Bảng này lưu việc HLV gán thủ công `track_id` → cầu thủ thật.

| Cột | Kiểu dữ liệu | Ràng buộc | Ghi chú |
|---|---|---|---|
| `id` | `UUID` | PK, `DEFAULT gen_random_uuid()` | |
| `match_id` | `UUID` | `NOT NULL`, FK → `matches.id` `ON DELETE CASCADE` | |
| `track_id` | `INTEGER` | `NOT NULL` | ID do ByteTrack/BoT-SORT sinh, chỉ có ý nghĩa trong 1 trận |
| `player_id` | `UUID` | `NULL`, FK → `players.id` `ON DELETE SET NULL` | `NULL` = HLV chưa gán. `SET NULL` để xóa cầu thủ không làm mất bản ghi track |
| `team_side` | `VARCHAR(10)` | `NOT NULL`, `CHECK (team_side IN ('home','away'))` | Do model phân loại, dùng để gợi ý danh sách cầu thủ khi gán |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |
| `updated_at` | `TIMESTAMPTZ` | `NOT NULL`, `DEFAULT now()` | |

**Index & ràng buộc:**
- `UNIQUE INDEX idx_track_mappings_match_track ON match_track_mappings(match_id, track_id)` — 1 track chỉ map 1 lần trong 1 trận
- `INDEX idx_track_mappings_player_id ON match_track_mappings(player_id)` — phục vụ query "cầu thủ X xuất hiện ở những trận nào"

**Endpoint liên quan:** `PUT /v1/matches/{match_id}/track-mappings` (Phase 6).

**Luồng sử dụng:** Glue ETL xuất Parquet khóa theo `track_id` → Frontend hiển thị "Player Track #1 (Home)" + dropdown → HLV gán → Backend lưu vào bảng này → Dashboard JOIN `track_id → player_id → players.full_name` để hiện tên thật.

---

## 3. State Machine của `matches.status`

```
pending ──(confirm-upload)──────────────────> uploaded      [Backend NestJS ghi]
uploaded ──(S3 Event → Lambda Dispatcher → SQS OK)──> processing   [status-updater-λ ghi]
processing ──(Worker xử lý xong, ghi kết quả)──> completed   [status-updater-λ ghi]
processing ──(Worker fail sau max retry, vào DLQ)──> failed   [status-updater-λ ghi]
```

**Ai được phép ghi `status`** (quyết định Q20 — Event-Driven Callback Pattern):

| Transition | Thành phần ghi | Cơ chế |
|---|---|---|
| `(tạo match)` → `pending` | Backend NestJS | `prisma.write` trực tiếp |
| `pending → uploaded` | Backend NestJS | `prisma.write` trực tiếp (khi client gọi `confirm-upload`) |
| `uploaded → processing` | `status-updater-lambda` | Lambda Dispatcher gửi message `{match_id, status:"processing", reason}` vào SQS `match-status-callbacks` |
| `processing → completed` | `status-updater-lambda` | AI Worker gửi message vào `match-status-callbacks` sau khi ghi xong kết quả |
| `processing → failed` | `status-updater-lambda` | AI Worker (hoặc redrive DLQ) gửi message vào `match-status-callbacks` |

**Lý do tách:** Worker và Lambda Dispatcher **không** có credential RDS (giữ least-privilege — xem `iam-security-design.md`). `status-updater-lambda` là **compute duy nhất** có secret ghi RDS, tránh RDS connection exhaustion khi Worker scale nhiều task.

**Quy tắc validate transition — phải implement ở CẢ 2 nơi** (vì có 2 codebase cùng ghi):
- `backend/src/matches/status-transition.ts` — validate `pending → uploaded`
- `lambda/status_updater/transitions.py` — validate 3 transition còn lại

Không cho phép nhảy trạng thái tùy ý (ví dụ `pending → completed`, hay quay lui `completed → processing`). CHECK constraint của DB chỉ chặn giá trị lạ, **không** chặn nhảy trạng thái sai — nên validate ở tầng application là bắt buộc. `failed` phải luôn kèm `error_message`.

**status-updater-lambda cần có DLQ riêng:** nếu Lambda này chết, status sẽ treo ở `processing` vĩnh viễn. Cấu hình DLQ + CloudWatch Alarm cho chính queue `match-status-callbacks` (xem `iam-security-design.md` và `terraform-structure.md` mục 3.5).

---

## 4. Chuẩn Prisma Schema tương ứng (tham chiếu để code)

> Prisma pin `~> 6.0` (quyết định Q15). `MatchStatus` dùng `enum` của Prisma để Prisma tự quản lý ràng buộc; `role`/`position` giữ `String` để linh hoạt mở rộng.

```prisma
// schema.prisma (minh họa cấu trúc — code thật cần đầy đủ hơn)

enum MatchStatus {
  pending
  uploaded
  processing
  completed
  failed
}

model User {
  id            String         @id @default(uuid()) @db.Uuid
  email         String         @unique @db.VarChar(255)
  passwordHash  String         @map("password_hash") @db.VarChar(255)
  fullName      String         @map("full_name") @db.VarChar(255)
  role          String         @default("coach") @db.VarChar(50)
  createdAt     DateTime       @default(now()) @map("created_at") @db.Timestamptz
  updatedAt     DateTime       @updatedAt @map("updated_at") @db.Timestamptz
  deletedAt     DateTime?      @map("deleted_at") @db.Timestamptz
  teams         Team[]
  refreshTokens RefreshToken[]

  @@map("users")
}

model RefreshToken {
  id        String    @id @default(uuid()) @db.Uuid
  userId    String    @map("user_id") @db.Uuid
  user      User      @relation(fields: [userId], references: [id], onDelete: Cascade)
  tokenHash String    @unique @map("token_hash") @db.VarChar(255)
  expiresAt DateTime  @map("expires_at") @db.Timestamptz
  revokedAt DateTime? @map("revoked_at") @db.Timestamptz
  createdAt DateTime  @default(now()) @map("created_at") @db.Timestamptz

  @@index([userId])
  @@map("refresh_tokens")
}

model Team {
  id        String    @id @default(uuid()) @db.Uuid
  ownerId   String    @map("owner_id") @db.Uuid
  owner     User      @relation(fields: [ownerId], references: [id], onDelete: Restrict)
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
  id            String              @id @default(uuid()) @db.Uuid
  teamId        String              @map("team_id") @db.Uuid
  team          Team                @relation(fields: [teamId], references: [id], onDelete: Cascade)
  opponentName  String              @map("opponent_name") @db.VarChar(255)
  matchDate     DateTime            @map("match_date") @db.Date
  videoS3Key    String?             @map("video_s3_key") @db.VarChar(512)
  durationSec   Int?                @map("duration_sec")
  status        MatchStatus         @default(pending)
  errorMessage  String?             @map("error_message")
  createdAt     DateTime            @default(now()) @map("created_at") @db.Timestamptz
  updatedAt     DateTime            @updatedAt @map("updated_at") @db.Timestamptz
  deletedAt     DateTime?           @map("deleted_at") @db.Timestamptz
  trackMappings MatchTrackMapping[]

  @@index([teamId])
  @@index([status])
  @@map("matches")
}

model Player {
  id            String              @id @default(uuid()) @db.Uuid
  teamId        String              @map("team_id") @db.Uuid
  team          Team                @relation(fields: [teamId], references: [id], onDelete: Cascade)
  fullName      String              @map("full_name") @db.VarChar(255)
  jerseyNumber  Int?                @map("jersey_number") @db.SmallInt
  position      String?             @db.VarChar(50)
  createdAt     DateTime            @default(now()) @map("created_at") @db.Timestamptz
  updatedAt     DateTime            @updatedAt @map("updated_at") @db.Timestamptz
  deletedAt     DateTime?           @map("deleted_at") @db.Timestamptz
  trackMappings MatchTrackMapping[]

  @@index([teamId])
  @@map("players")
}

model MatchTrackMapping {
  id        String   @id @default(uuid()) @db.Uuid
  matchId   String   @map("match_id") @db.Uuid
  match     Match    @relation(fields: [matchId], references: [id], onDelete: Cascade)
  trackId   Int      @map("track_id")
  playerId  String?  @map("player_id") @db.Uuid
  player    Player?  @relation(fields: [playerId], references: [id], onDelete: SetNull)
  teamSide  String   @map("team_side") @db.VarChar(10)
  createdAt DateTime @default(now()) @map("created_at") @db.Timestamptz
  updatedAt DateTime @updatedAt @map("updated_at") @db.Timestamptz

  @@unique([matchId, trackId])
  @@index([playerId])
  @@map("match_track_mappings")
}
```

**Ghi chú về CHECK constraint:** `role`, `position`, `team_side` khai báo là `String` nên CHECK constraint không sinh tự động — cần thêm qua **raw SQL migration** sau khi Prisma generate migration ban đầu:

```sql
ALTER TABLE users ADD CONSTRAINT chk_users_role
  CHECK (role IN ('coach', 'admin'));

ALTER TABLE players ADD CONSTRAINT chk_players_position
  CHECK (position IN ('goalkeeper','defender','midfielder','forward'));

ALTER TABLE players ADD CONSTRAINT chk_players_jersey
  CHECK (jersey_number BETWEEN 1 AND 99);

ALTER TABLE match_track_mappings ADD CONSTRAINT chk_track_team_side
  CHECK (team_side IN ('home','away'));

-- Unique index có điều kiện (Prisma không hỗ trợ partial unique index)
CREATE UNIQUE INDEX idx_players_team_jersey
  ON players(team_id, jersey_number) WHERE deleted_at IS NULL;
```

`MatchStatus` dùng Prisma `enum` nên Prisma tự tạo PostgreSQL enum type, không cần CHECK thủ công.

---

## 5. Việc cần làm tiếp theo

Sau khi có Database Schema chi tiết này, kết hợp với `docs/data-contracts.md` (schema DynamoDB + S3 JSON) và `docs/backend-architecture.md` (cấu trúc NestJS), Backend đã đủ đặc tả để bắt đầu code Entity/Migration ngay từ Phase 0.

