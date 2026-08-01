# MatchLens — Backend Architecture (NestJS)

> Cấu trúc kiến trúc chi tiết cho Backend API Service, viết bằng NestJS + TypeScript + pnpm. Cập nhật thay thế cho phần tech stack cũ (NestJS) đã đề cập ở `docs/api-design.md` — tài liệu này là nguồn tham chiếu chính thức cho cấu trúc code Backend.

---

## 1. Tech stack Backend chốt chính thức

| Thành phần | Lựa chọn |
|---|---|
| Framework | NestJS (TypeScript) |
| Package manager | pnpm |
| ORM | Prisma |
| Database | PostgreSQL (RDS Master + Read Replica) |
| Validation | `class-validator` + `class-transformer` (chuẩn NestJS DTO) |
| Auth | `@nestjs/jwt`, `passport-jwt`, `bcrypt` |
| AWS SDK | `@aws-sdk/client-s3`, `@aws-sdk/client-dynamodb`, `@aws-sdk/client-sqs`, `@aws-sdk/client-secrets-manager`, `@aws-sdk/s3-request-presigner` |
| Testing | Jest (mặc định của NestJS) |
| API Documentation | `@nestjs/swagger` (tự sinh OpenAPI từ DTO/decorator) |

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
│   │   │   └── resource-ownership.guard.ts    (chống IDOR, xem api-design.md mục 8)
│   │   ├── filters/
│   │   │   └── http-exception.filter.ts        (chuẩn hóa response lỗi theo api-design.md mục 1)
│   │   └── interceptors/
│   │       └── response-transform.interceptor.ts (chuẩn hóa response wrapper thành công)
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
│   │   ├── s3.service.ts                        (tạo presigned URL, get object)
│   │   ├── dynamodb.service.ts                  (query MatchEvents)
│   │   ├── secrets-manager.service.ts           (lấy DB credentials lúc bootstrap)
│   │   └── athena.service.ts                    (nếu chọn phương án query trực tiếp thay vì cache — xem api-design.md mục 9)
│   │
│   ├── auth/
│   │   ├── auth.module.ts
│   │   ├── auth.controller.ts
│   │   ├── auth.service.ts
│   │   ├── strategies/
│   │   │   └── jwt.strategy.ts
│   │   └── dto/
│   │       ├── register.dto.ts
│   │       ├── login.dto.ts
│   │       └── refresh-token.dto.ts
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
│   ├── players/
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
│       └── dto/
│           ├── create-match.dto.ts
│           ├── upload-url-request.dto.ts
│           └── confirm-upload.dto.ts
│
├── prisma/
│   ├── schema.prisma
│   └── migrations/
│
├── test/
│   └── (unit test theo từng module, đặt cạnh file .spec.ts hoặc trong test/ tùy convention nhóm)
│
├── Dockerfile
├── package.json
├── pnpm-lock.yaml
├── tsconfig.json
└── nest-cli.json
```

**Nguyên tắc tổ chức module:** mỗi domain nghiệp vụ (`auth`, `teams`, `players`, `matches`) là 1 module riêng theo đúng chuẩn NestJS, có controller/service/dto riêng. `common/` chứa thành phần dùng chung xuyên suốt (guard, filter, interceptor). `aws/` và `prisma/` là 2 module hạ tầng (infrastructure module), được các domain module khác import vào khi cần.

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

```typescript
// src/prisma/prisma.service.ts

import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  public readonly write: PrismaClient;   // Kết nối tới RDS Master
  public readonly read: PrismaClient;    // Kết nối tới RDS Read Replica

  constructor() {
    this.write = new PrismaClient({
      datasources: { db: { url: process.env.DATABASE_URL_MASTER } },
    });
    this.read = new PrismaClient({
      datasources: { db: { url: process.env.DATABASE_URL_REPLICA } },
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
- Thao tác **ghi** (create/update/delete) → luôn dùng `prisma.write`
- Thao tác **đọc danh sách, đọc không cần real-time tuyệt đối** → dùng `prisma.read`
- Thao tác **đọc ngay sau khi vừa ghi trong cùng 1 request** (ví dụ trả về object vừa tạo) → dùng `prisma.write` để tránh replication lag (đã nêu ở `docs/database-schema.md` mục 1.1.1), hoặc đơn giản hơn là trả thẳng dữ liệu từ kết quả `create()` mà không cần query lại

### 4.4. Biến môi trường cần thiết

```
DATABASE_URL_MASTER=postgresql://user:pass@matchlens-dev-postgres-master.xxx.rds.amazonaws.com:5432/matchlens
DATABASE_URL_REPLICA=postgresql://user:pass@matchlens-dev-postgres-replica.xxx.rds.amazonaws.com:5432/matchlens
```

Cả 2 giá trị này lấy từ Secrets Manager lúc container khởi động (qua `secrets-manager.service.ts`), không hardcode trong `.env` khi deploy thật (chỉ dùng `.env` cho local development).

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

  async generateUploadUrl(teamId: string, matchId: string, contentType: string): Promise<{ url: string; key: string }> {
    const key = `raw-videos/${teamId}/${matchId}/original.mp4`;
    const command = new PutObjectCommand({
      Bucket: this.config.get('S3_RAW_VIDEOS_BUCKET'),
      Key: key,
      ContentType: contentType,
    });
    const url = await getSignedUrl(this.client, command, { expiresIn: 900 }); // 15 phút, theo api-design.md
    return { url, key };
  }
}
```

Đường dẫn `key` sinh ra ở đây phải khớp chính xác với convention đã định nghĩa ở `docs/data-model.md` mục 3.2.

---

## 6. Đọc DynamoDB (MatchEvents) — ví dụ code minh họa

```typescript
// src/aws/dynamodb.service.ts

@Injectable()
export class DynamoDbService {
  private client: DynamoDBDocumentClient;

  async getHighlightsByMatch(matchId: string) {
    const command = new QueryCommand({
      TableName: 'matchlens-dev-match-events',
      KeyConditionExpression: 'match_id = :matchId',
      ExpressionAttributeValues: { ':matchId': matchId },
    });
    const result = await this.client.send(command);
    return result.Items; // Đúng schema đã định nghĩa ở docs/data-contracts.md mục 2.2
  }
}
```

---

## 7. Guard chống IDOR (Resource Ownership) — ví dụ code minh họa

```typescript
// src/common/guards/resource-ownership.guard.ts

@Injectable()
export class ResourceOwnershipGuard implements CanActivate {
  constructor(private prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const userId = request.user.id; // Gắn từ JwtStrategy sau khi verify token
    const teamId = request.params.team_id;

    const team = await this.prisma.read.team.findUnique({ where: { id: teamId } });
    if (!team || team.ownerId !== userId) {
      throw new ForbiddenException('Bạn không có quyền truy cập tài nguyên này');
    }
    return true;
  }
}
```

Áp dụng Guard này cho mọi endpoint có `team_id` trong path — đúng nguyên tắc đã nêu ở `api-design.md` mục 8.

---

## 8. Dockerfile chuẩn cho Backend (multi-stage build, tối ưu image size)

```dockerfile
# backend/Dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY pnpm-lock.yaml package.json ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm prisma generate
RUN pnpm build

FROM node:20-alpine AS production
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/prisma ./prisma
COPY package.json ./
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

**Lý do multi-stage build:** giảm kích thước image cuối cùng (không mang theo devDependencies, source TypeScript gốc), tăng tốc độ pull image khi deploy qua ECS — đúng thực hành chuẩn khi build image cho production.

---

## 9. Câu hỏi còn mở — cần quyết định trước khi code

- [ ] Có cần thêm `HealthModule` (endpoint `/health`) để ECS Health Check và ALB Target Group Health Check dùng không? — khuyến nghị **có**, nên thêm ngay từ Phase 0 vì ECS Service cần endpoint health check hoạt động mới coi deploy là thành công
- [ ] Rate-limiting (`@nestjs/throttler`) áp dụng ở tầng NestJS hay để API Gateway/ALB xử lý? — khuyến nghị áp dụng ở NestJS cho endpoint `/upload-url` cụ thể (theo câu hỏi mở đã nêu ở `api-design.md` mục 9)
- [ ] Logging structure (Winston/Pino) tích hợp với CloudWatch Logs theo format nào để dễ dùng CloudWatch Log Insights query sau này?

---

## 10. Việc cần làm tiếp theo

Với 3 tài liệu bổ sung này (`database-schema.md`, `data-contracts.md`, `backend-architecture.md`), toàn bộ Design Phase của MatchLens đã thực sự đầy đủ để bắt đầu code — cả phần hạ tầng (Terraform) lẫn phần ứng dụng (Backend NestJS, AI Worker Python). Cần cập nhật lại `CLAUDE.md` mục 2 để thêm 3 file này vào danh sách tài liệu bắt buộc đọc.

