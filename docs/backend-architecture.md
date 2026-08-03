# MatchLens — Backend Architecture (NestJS)

> Cấu trúc kiến trúc chi tiết cho Backend API Service, viết bằng NestJS + TypeScript + pnpm. Cập nhật thay thế cho phần tech stack cũ (NestJS) đã đề cập ở `docs/api-design.md` — tài liệu này là nguồn tham chiếu chính thức cho cấu trúc code Backend.

---

## 1. Tech stack Backend chốt chính thức

| Thành phần | Lựa chọn |
|---|---|
| Framework | NestJS (TypeScript) |
| Runtime | **Node.js 22 LTS** (`node:22-alpine` trong Dockerfile — quyết định Q15) |
| Package manager | pnpm |
| ORM | **Prisma `~> 6.0`** (dùng cú pháp `datasourceUrl` — quyết định Q15) |
| Database | PostgreSQL (RDS Master + Read Replica) |
| Validation | `class-validator` + `class-transformer` (chuẩn NestJS DTO) |
| Serialization | `ClassSerializerInterceptor` + `@Expose({ name })` — map camelCase ↔ snake_case (quyết định Q13) |
| Auth | `@nestjs/jwt` (**RS256**), `passport-jwt`, `bcrypt` (cost 10-12) |
| Rate limiting | `@nestjs/throttler` — 10 req/phút/user cho `/upload-url` (quyết định Q33) |
| Logging | **Pino** (`nestjs-pino`) — JSON structured log cho CloudWatch Log Insights (quyết định Q33) |
| AWS SDK | `@aws-sdk/client-s3`, `@aws-sdk/client-dynamodb`, `@aws-sdk/client-secrets-manager`, `@aws-sdk/s3-request-presigner`, `@aws-sdk/cloudfront-signer` |
| Testing | Jest (mặc định của NestJS) |
| API Documentation | `@nestjs/swagger` (tự sinh OpenAPI từ DTO/decorator) |

**Lưu ý:** `@aws-sdk/client-sqs` **không** nằm trong danh sách — Backend không tương tác với SQS (quyết định Q20: Backend ghi RDS trực tiếp cho 2 transition đầu, phần còn lại do Lambda xử lý). Thêm `@aws-sdk/cloudfront-signer` để sinh CloudFront Signed URL (quyết định Q23).

---

## 2. Cấu trúc thư mục Module

```
backend/
├── src/
│   ├── main.ts
│   ├── app.module.ts
│   ├── common/
│   │   ├── decorators/
│   │   │   └── current-user.decorator.ts
│   │   ├── guards/
│   │   │   ├── jwt-auth.guard.ts
│   │   │   ├── team-ownership.guard.ts          (route có :team_id)
│   │   │   └── match-ownership.guard.ts         (route chỉ có :match_id — quyết định Q11)
│   │   ├── filters/
│   │   │   └── http-exception.filter.ts         (chuẩn hóa response lỗi theo api-design.md mục 1)
│   │   └── interceptors/
│   │       └── response-transform.interceptor.ts (wrapper {success,data,error} — chạy SAU serializer)
│   │
│   ├── config/
│   │   ├── configuration.ts
│   │   └── validation.schema.ts                 (validate biến môi trường bằng Joi)
│   │
│   ├── prisma/
│   │   ├── prisma.module.ts
│   │   └── prisma.service.ts                    (quản lý 2 PrismaClient: write + read, xem mục 4)
│   │
│   ├── aws/
│   │   ├── aws.module.ts
│   │   ├── s3.service.ts                        (tạo presigned URL upload)
│   │   ├── cloudfront.service.ts                (sinh CloudFront Signed URL — quyết định Q23)
│   │   ├── dynamodb.service.ts                  (query match-events, filter MARKER#)
│   │   ├── secrets-manager.service.ts           (lấy DB credentials + JWT keypair lúc bootstrap)
│   │   └── athena.service.ts                    (Phase 6)
│   │
│   ├── health/
│   │   ├── health.module.ts
│   │   └── health.controller.ts                 (GET /health — quyết định Q16)
│   │
│   ├── auth/
│   │   ├── auth.module.ts
│   │   ├── auth.controller.ts
│   │   ├── auth.service.ts
│   │   ├── refresh-token.service.ts             (quản lý bảng refresh_tokens — quyết định Q12)
│   │   ├── strategies/
│   │   │   └── jwt.strategy.ts                  (RS256, verify bằng public key)
│   │   └── dto/
│   │       ├── register.dto.ts
│   │       ├── login.dto.ts
│   │       ├── refresh-token.dto.ts
│   │       └── logout.dto.ts
│   │
│   ├── users/
│   │   ├── users.module.ts
│   │   ├── users.service.ts
│   │   └── users.repository.ts
│   │
│   ├── teams/
│   │   ├── teams.module.ts
│   │   ├── teams.controller.ts
│   │   ├── teams.service.ts
│   │   └── dto/
│   │       └── create-team.dto.ts
│   │
│   ├── players/                                 (module riêng — quyết định Q17)
│   │   ├── players.module.ts
│   │   ├── players.controller.ts
│   │   ├── players.service.ts
│   │   └── dto/
│   │       ├── create-player.dto.ts
│   │       └── update-player.dto.ts
│   │
│   └── matches/
│       ├── matches.module.ts
│       ├── matches.controller.ts
│       ├── matches.service.ts
│       ├── status-transition.ts                 (validate state machine — quyết định Q20)
│       ├── track-mappings.service.ts            (Phase 6 — quyết định Q25/D1)
│       └── dto/
│           ├── create-match.dto.ts
│           ├── upload-url-request.dto.ts
│           ├── confirm-upload.dto.ts
│           └── update-track-mappings.dto.ts
│
├── prisma/
│   ├── schema.prisma
│   └── migrations/
│
├── test/
├── Dockerfile
├── package.json
├── pnpm-lock.yaml
├── tsconfig.json
└── nest-cli.json
```

**Nguyên tắc tổ chức module:** mỗi domain nghiệp vụ (`auth`, `users`, `teams`, `players`, `matches`) là 1 module riêng theo chuẩn NestJS. `common/` chứa thành phần dùng chung (guard, filter, interceptor). `prisma/`, `aws/` là infrastructure module. `health/` tách riêng vì có yêu cầu đặc biệt (không auth, không wrapper).

**Thay đổi so với bản thiết kế trước:**
- Tách `resource-ownership.guard.ts` thành **2 guard** (`team-ownership` cho route có `:team_id`, `match-ownership` cho route chỉ có `:match_id`) — vì logic query khác nhau (quyết định Q11)
- Thêm `health/`, `refresh-token.service.ts`, `cloudfront.service.ts`, `status-transition.ts`, `track-mappings.service.ts`
- `players/` là module riêng, không gộp vào `teams/` (quyết định Q17)

---

## 3. Luồng phụ thuộc giữa các module

```
AppModule
  ├── ConfigModule (global)
  ├── PrismaModule (global)
  ├── AwsModule (global)
  ├── AuthModule
  │     depends on: PrismaModule, UsersModule
  ├── UsersModule
  │     depends on: PrismaModule
  ├── TeamsModule
  │     depends on: PrismaModule
  ├── PlayersModule
  │     depends on: PrismaModule
  └── MatchesModule
        depends on: PrismaModule, AwsModule (S3 presigned URL, DynamoDB query)
```

**Import dùng `@Global()` cho `PrismaModule` và `AwsModule`** để tránh phải import lặp lại ở từng domain module — đây là 2 module hạ tầng dùng ở hầu hết mọi nơi.

---

## 4. Xử lý Read Replica trong code (điểm kỹ thuật quan trọng)

### 4.1. Vấn đề

Prisma không hỗ trợ tự động route query đọc/ghi tới 2 datasource khác nhau (Master/Read Replica) như một số ORM khác (ví dụ TypeORM có sẵn cơ chế `replication` config). Cần tự implement.

### 4.2. Giải pháp: 2 PrismaClient instance riêng biệt

> **Prisma 6 dùng `datasourceUrl`** (số ít, string) thay cho `datasources: { db: { url } }` của Prisma 5 (quyết định Q15).

```typescript
// src/prisma/prisma.service.ts

import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  public readonly write: PrismaClient;   // Kết nối tới RDS Master
  public readonly read: PrismaClient;    // Kết nối tới RDS Read Replica

  constructor(private config: ConfigService) {
    this.write = new PrismaClient({
      datasourceUrl: this.config.get<string>('DATABASE_URL_MASTER'),
    });
    this.read = new PrismaClient({
      datasourceUrl: this.config.get<string>('DATABASE_URL_REPLICA'),
    });
  }

  async onModuleInit() {
    await this.write.$connect();
    await this.read.$connect();
  }

  async onModuleDestroy() {
    await this.write.$disconnect();
    await this.read.$disconnect();
  }
}
```

**Ở môi trường `dev`, cả 2 biến trỏ cùng endpoint Master** (quyết định Q3) — không có Read Replica vật lý. Code trên **không cần thay đổi** giữa các môi trường, chỉ khác giá trị biến môi trường. Nhờ vậy quy tắc chọn client được viết đúng ngay từ dev.

### 4.3. Quy tắc sử dụng trong Service Layer

```typescript
// Ví dụ trong matches.service.ts

@Injectable()
export class MatchesService {
  constructor(private prisma: PrismaService) {}

  // GHI -> luôn dùng this.prisma.write
  async createMatch(dto: CreateMatchDto, teamId: string) {
    return this.prisma.write.match.create({
      data: { ...dto, teamId, status: 'pending' },
    });
  }

  // ĐỌC tải cao (danh sách) -> dùng this.prisma.read
  async findAllByTeam(teamId: string) {
    return this.prisma.read.match.findMany({ where: { teamId } });
  }

  // ĐỌC ngay sau khi ghi (cần dữ liệu mới nhất) -> dùng this.prisma.write để tránh replication lag
  async getMatchStatusRightAfterCreate(matchId: string) {
    return this.prisma.write.match.findUnique({ where: { id: matchId } });
  }
}
```

**Quy tắc bắt buộc:**

| Tình huống | Client |
|---|---|
| Thao tác **ghi** (create/update/delete) | `prisma.write` — luôn luôn |
| Thao tác **đọc danh sách**, đọc không cần real-time tuyệt đối | `prisma.read` |
| Thao tác **đọc ngay sau khi vừa ghi trong cùng request** | `prisma.write`, hoặc tốt hơn: trả thẳng dữ liệu từ kết quả `create()` không query lại |
| **Guard kiểm tra phân quyền** (`team-ownership`, `match-ownership`) | **`prisma.write` — BẮT BUỘC** (quyết định Q11) |

> ⚠️ **Ngoại lệ quan trọng — guard phải dùng Master:** kiểm tra phân quyền đọc từ Read Replica có replication lag sẽ gây `403 FORBIDDEN` **oan** ngay sau khi user vừa tạo team/match. Đây là ngoại lệ có chủ đích của quy tắc "đọc thì dùng replica".

### 4.4. Biến môi trường cần thiết

```
DATABASE_URL_MASTER=postgresql://user:pass@matchlens-dev-postgres.xxx.rds.amazonaws.com:5432/matchlens
DATABASE_URL_REPLICA=postgresql://user:pass@matchlens-dev-postgres.xxx.rds.amazonaws.com:5432/matchlens
AWS_REGION=ap-southeast-1
S3_RAW_VIDEOS_BUCKET=matchlens-dev-raw-videos
DYNAMODB_MATCH_EVENTS_TABLE=matchlens-dev-match-events
CDN_DOMAIN=cdn.matchlens.com
DB_SECRET_NAME=matchlens-dev-db-credentials-secret
JWT_KEYPAIR_SECRET_NAME=matchlens-dev-jwt-keypair-secret
CLOUDFRONT_SIGNING_KEY_SECRET_NAME=matchlens-dev-cloudfront-signing-key-secret
CLOUDFRONT_KEY_PAIR_ID=K2XXXXXXXXXXXX
MAX_UPLOAD_SIZE_BYTES=2147483648
```

**Lưu ý ví dụ trên là môi trường `dev`:** `DATABASE_URL_REPLICA` trỏ **cùng endpoint** với Master vì dev không có Read Replica vật lý (quyết định Q3). Ở staging/prod, giá trị này là `matchlens-{env}-postgres-replica.xxx.rds.amazonaws.com`.

Credential (username/password DB, JWT keypair, CloudFront private key) lấy từ **Secrets Manager lúc container khởi động** qua `secrets-manager.service.ts`, không hardcode trong `.env` khi deploy thật (`.env` chỉ dùng cho local development).

---

## 5. Xử lý Upload Video (S3 Presigned URL) — ví dụ code minh họa

```typescript
// src/aws/s3.service.ts

@Injectable()
export class S3Service {
  private client: S3Client;

  constructor(private config: ConfigService) {
    this.client = new S3Client({ region: this.config.get('AWS_REGION') });
  }

  async generateUploadUrl(
    teamId: string,
    matchId: string,
    contentType: string,
  ): Promise<{ url: string; key: string }> {
    // Key KHÔNG có prefix 'raw-videos/' — không lặp lại tên bucket (quyết định Q18)
    const key = `${teamId}/${matchId}/original.mp4`;
    const command = new PutObjectCommand({
      Bucket: this.config.get('S3_RAW_VIDEOS_BUCKET'),
      Key: key,
      ContentType: contentType,
    });
    const url = await getSignedUrl(this.client, command, { expiresIn: 900 }); // 15 phút
    return { url, key };
  }
}
```

Đường dẫn `key` phải khớp chính xác convention ở `docs/data-model.md` mục 3.2 và `docs/data-contracts.md` mục 1.

---

## 5.1. Sinh CloudFront Signed URL cho highlight (quyết định Q23)

Bucket `processed-highlights` là **private hoàn toàn** (chỉ CloudFront truy cập qua OAC), nên Backend không dùng `s3:GetObject` mà sinh CloudFront Signed URL:

```typescript
// src/aws/cloudfront.service.ts

import { getSignedUrl } from '@aws-sdk/cloudfront-signer';

@Injectable()
export class CloudFrontService {
  private privateKey: string;      // load từ Secrets Manager lúc bootstrap
  private keyPairId: string;

  signClipUrl(s3Key: string): string {
    const expiresAt = new Date(Date.now() + 4 * 60 * 60 * 1000); // 4 giờ
    return getSignedUrl({
      url: `https://${this.config.get('CDN_DOMAIN')}/${s3Key}`,
      keyPairId: this.keyPairId,
      privateKey: this.privateKey,
      dateLessThan: expiresAt.toISOString(),
    });
  }
}
```

Private key lấy từ secret `matchlens-{env}-cloudfront-signing-key-secret`. **Không** dùng chung với keypair JWT — 2 mục đích khác nhau, 2 secret khác nhau (quyết định D3).

---

## 6. Đọc DynamoDB (match-events) — ví dụ code minh họa

```typescript
// src/aws/dynamodb.service.ts

@Injectable()
export class DynamoDbService {
  private client: DynamoDBDocumentClient;

  async getHighlightsByMatch(matchId: string) {
    const command = new QueryCommand({
      TableName: this.config.get('DYNAMODB_MATCH_EVENTS_TABLE'), // matchlens-{env}-match-events
      KeyConditionExpression: 'match_id = :matchId',
      // BẮT BUỘC loại bỏ item cờ idempotency MARKER#COMPLETED (quyết định D5)
      FilterExpression: 'NOT begins_with(event_id, :markerPrefix)',
      ExpressionAttributeValues: {
        ':matchId': matchId,
        ':markerPrefix': 'MARKER#',
      },
    });
    const result = await this.client.send(command);
    return result.Items; // Đúng schema ở docs/data-contracts.md mục 2.2
  }
}
```

> ⚠️ **`FilterExpression` loại bỏ `MARKER#` là bắt buộc.** Worker ghi 1 item `event_id = "MARKER#COMPLETED"` làm cờ idempotency; item này thiếu `event_type`, `highlight_clip_s3_key`, `confidence_score`. Nếu không filter, HLV sẽ thấy 1 highlight rỗng không phát được (xem `docs/data-contracts.md` mục 2.3).

---

## 7. Guard chống IDOR (Resource Ownership) — 2 biến thể

### 7.1. `TeamOwnershipGuard` — route có `:team_id`

```typescript
// src/common/guards/team-ownership.guard.ts

@Injectable()
export class TeamOwnershipGuard implements CanActivate {
  constructor(private prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const userId = request.user.id;          // gắn từ JwtStrategy (quyết định Q14)
    const teamId = request.params.team_id;

    // Dùng prisma.write (Master) — tránh 403 oan do replication lag (quyết định Q11)
    const team = await this.prisma.write.team.findFirst({
      where: { id: teamId, deletedAt: null },
    });
    if (!team) throw new NotFoundException('Không tìm thấy đội bóng');
    if (team.ownerId !== userId && request.user.role !== 'admin') {
      throw new ForbiddenException('Bạn không có quyền truy cập tài nguyên này');
    }
    return true;
  }
}
```

### 7.2. `MatchOwnershipGuard` — route chỉ có `:match_id` (quyết định Q11)

Áp dụng cho `/matches/{match_id}/upload-url`, `/confirm-upload`, `/status`, `/highlights`, `/stats`, `/track-mappings`, `DELETE /matches/{match_id}` — những endpoint **không có `team_id` trong path**, nên guard ở mục 7.1 không bảo vệ được.

```typescript
// src/common/guards/match-ownership.guard.ts

@Injectable()
export class MatchOwnershipGuard implements CanActivate {
  constructor(private prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const userId = request.user.id;
    const matchId = request.params.match_id;

    // JOIN sang team để lấy owner_id — vẫn dùng Master
    const match = await this.prisma.write.match.findFirst({
      where: { id: matchId, deletedAt: null },
      select: { id: true, team: { select: { ownerId: true } } },
    });
    if (!match) throw new NotFoundException('Không tìm thấy trận đấu');
    if (match.team.ownerId !== userId && request.user.role !== 'admin') {
      throw new ForbiddenException('Bạn không có quyền truy cập tài nguyên này');
    }
    return true;
  }
}
```

Đây là lỗ hổng IDOR đã được phát hiện trong audit: bản thiết kế trước chỉ có 1 guard đọc `request.params.team_id`, nên 6 endpoint quan trọng nhất của luồng highlight **không được bảo vệ**.

---

## 7.3. Validate State Machine `matches.status` (quyết định Q20)

```typescript
// src/matches/status-transition.ts

export const ALLOWED_TRANSITIONS: Record<MatchStatus, MatchStatus[]> = {
  pending:    ['uploaded'],
  uploaded:   ['processing'],
  processing: ['completed', 'failed'],
  completed:  [],
  failed:     [],
};

export function assertValidTransition(from: MatchStatus, to: MatchStatus): void {
  if (!ALLOWED_TRANSITIONS[from].includes(to)) {
    throw new ConflictException(
      `Không thể chuyển trạng thái từ '${from}' sang '${to}'`,
    );
  }
}
```

**Backend chỉ ghi 2 transition:** `(tạo match) → pending` và `pending → uploaded` (khi client gọi `confirm-upload`). Ba transition còn lại do Lambda `status-updater-fn` ghi.

> ⚠️ **Logic này tồn tại ở 2 nơi** (`backend/src/matches/status-transition.ts` và `lambda/status_updater/transitions.py`) — sửa 1 bên **bắt buộc** sửa bên còn lại. Đây là đánh đổi đã được chấp nhận ở quyết định Q20 để `confirm-upload` phản hồi tức thì cho UI.

---

## 8. Dockerfile chuẩn cho Backend (multi-stage build, tối ưu image size)

```dockerfile
# backend/Dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY pnpm-lock.yaml package.json ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm prisma generate
RUN pnpm build

FROM node:22-alpine AS production
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/prisma ./prisma
COPY package.json ./
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD node -e "require('http').get('http://localhost:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"
CMD ["node", "dist/main.js"]
```

**Lý do multi-stage build:** giảm kích thước image cuối (không mang theo devDependencies, source TypeScript gốc), tăng tốc pull image khi deploy qua ECS.

**Node 22 LTS** theo quyết định Q15. `HEALTHCHECK` gọi `/health` (quyết định Q16) để ECS biết container có thực sự sẵn sàng.

---

## 9. Câu hỏi còn mở — ĐÃ CHỐT TOÀN BỘ

| Câu hỏi | Quyết định | Mã ADR |
|---|---|---|
| Có cần `HealthModule` (`/health`)? | **Có, ngay Phase 0** — trả `{status, db, timestamp}`, không auth, không bọc wrapper | Q16 |
| Rate-limiting ở NestJS hay ALB? | **NestJS** (`@nestjs/throttler`), 10 req/phút/user cho `/upload-url` | Q33 |
| Logging dùng gì? | **Pino** (`nestjs-pino`) — JSON structured log, nhanh hơn Winston, tối ưu CloudWatch Log Insights | Q33 |

Chi tiết đầy đủ: `docs/decision-record.md`.

---

## 10. Thứ tự Interceptor & Serialization (quyết định Q13, D5)

Toàn bộ response đi qua **2 lớp xử lý, thứ tự bắt buộc**:

```
Controller trả về entity/DTO (camelCase trong code)
        │
        ▼
1. ClassSerializerInterceptor      → map camelCase sang snake_case qua @Expose({ name })
        │
        ▼
2. ResponseTransformInterceptor    → bọc thành { success: true, data: {...}, error: null }
        │
        ▼
Client nhận JSON snake_case đã bọc wrapper
```

```typescript
// src/main.ts — thứ tự đăng ký quyết định thứ tự chạy
app.useGlobalInterceptors(
  new ClassSerializerInterceptor(app.get(Reflector))),  // chạy trước
  new ResponseTransformInterceptor(),                    // chạy sau
);
```

**Ví dụ DTO:**

```typescript
export class MatchResponseDto {
  @Expose({ name: 'match_id' })    id: string;
  @Expose({ name: 'team_id' })     teamId: string;
  @Expose({ name: 'opponent_name' }) opponentName: string;
  @Expose({ name: 'processing_status' }) status: MatchStatus;  // Q10: DB 'status' → API 'processing_status'
  @Expose({ name: 'video_s3_key' }) videoS3Key: string | null;
  @Expose({ name: 'created_at' })  createdAt: Date;
}
```

**Ngoại lệ:** endpoint `/health` **loại khỏi cả 2 interceptor** — ALB cần response phẳng `{status, db, timestamp}`, không bọc wrapper.

---

## 11. Việc cần làm tiếp theo

Backend Architecture này đã đồng bộ với `docs/decision-record.md`. Trước khi code Phase 0, đọc lại mục 4.3 (quy tắc chọn Prisma client), mục 7 (2 guard chống IDOR), và mục 10 (thứ tự interceptor) — đây là 3 điểm dễ implement sai nhất.

