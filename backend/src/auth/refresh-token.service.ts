import { Injectable } from "@nestjs/common";
import { createHash } from "node:crypto";
import { PrismaService } from "src/prisma/prisma.service";

@Injectable()
export class RefreshTokenService {
    constructor(private readonly prisma: PrismaService) { }

    hashToken(token: string): string {
        return createHash('sha256').update(token).digest('hex');
    }

    async create(userId: string, refreshToken: string, expiresAt: Date): Promise<void> {
        await this.prisma.write.refreshToken.create({
            data: {
                userId,
                tokenHash: this.hashToken(refreshToken),
                expiresAt,
            }
        });
    }

    async findActiveToken(refreshToken: string) {
        return this.prisma.write.refreshToken.findFirst({
            where: {
                tokenHash: this.hashToken(refreshToken),
                revokedAt: null,
                expiresAt: {
                    gt: new Date()
                },
            },
        });
    }

    async revokeByRawToken(refreshToken: string): Promise<void> {
        await this.prisma.write.refreshToken.updateMany({
            where: {
                tokenHash: this.hashToken(refreshToken),
                revokedAt: null
            },
            data: {
                revokedAt: new Date()
            },
        });
    }
}