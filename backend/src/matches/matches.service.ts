import { BadRequestException, ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "src/prisma/prisma.service";
import { CreateMatchDto } from "./dto/create-match.dto";
import { MatchResponseDto } from "./dto/match-response.dto";
import { MatchListItemDto } from "./dto/match-list-item.dto";
import { MatchStatus } from "@prisma/client";
import { UploadUrlRequestDto } from "./dto/upload-url-request.dto";
import { UploadUrlResponseDto } from "./dto/upload-url-response.dto";
import { S3Service } from "src/aws/s3.service";
import { ConfigService } from "@nestjs/config";
import { assertValidTransition } from "./status-transition";
import { MatchStatusResponseDto } from "./dto/match-status-response.dto";

@Injectable()
export class MatchesService {
    private static readonly ALLOWED_UPLOAD_CONTENT_TYPES = [
        'video/mp4',
        'video/quicktime',
    ];

    private readonly maxUploadSizeBytes: number;

    constructor(
        private readonly prisma: PrismaService,
        private readonly s3Service: S3Service,
        private readonly configService: ConfigService
    ) {
        this.maxUploadSizeBytes = this.configService.getOrThrow<number>(
            'upload.maxUploadSizeBytes',
        );
    }

    async create(teamId: string, dto: CreateMatchDto): Promise<MatchResponseDto> {
        assertValidTransition('INIT', 'pending');

        const match = await this.prisma.write.match.create({
            data: {
                teamId,
                opponentName: dto.opponentName,
                matchDate: new Date(dto.matchDate),
                status: 'pending',
            },
        });

        return new MatchResponseDto(match);
    }

    async findAllByTeam(teamId: string): Promise<MatchListItemDto[]> {
        const matches = await this.prisma.read.match.findMany({
            where: {
                teamId,
                deletedAt: null
            },
            orderBy: { matchDate: 'desc' },
        });

        return matches.map((match) => new MatchListItemDto(match));
    }

    async createUploadUrl(
        matchId: string,
        teamId: string,
        currentStatus: MatchStatus,
        dto: UploadUrlRequestDto
    ): Promise<UploadUrlResponseDto> {
        this.validateUploadRequest(dto);

        if (currentStatus != 'pending') {
            throw new ConflictException({
                code: 'INVALID_STATE_TRANSITION',
                message: 'Upload URL can only be created when match status is pending',
            });
        }

        const s3Key = this.buildRawVideoKey(teamId, matchId);
        const { uploadUrl, expiresIn } = await this.s3Service.createPresignedUploadUrl({
            key: s3Key,
            contentType: dto.contentType,
        });

        return new UploadUrlResponseDto({
            uploadUrl,
            s3Key,
            expiresIn
        });
    }

    async confirmUpload(matchId: string): Promise<MatchResponseDto> {
        const match = await this.prisma.write.match.findFirst({
            where: {
                id: matchId,
                deletedAt: null,
            },
            select: {
                id: true,
                teamId: true,
                opponentName: true,
                matchDate: true,
                videoS3Key: true,
                status: true,
                createdAt: true
            },
        });

        if (!match) {
            throw new NotFoundException("Match not found.");
        }

        assertValidTransition(match.status, 'uploaded');

        const updatedMatch = await this.prisma.write.match.update({
            where: { id: matchId },
            data: {
                videoS3Key: this.buildRawVideoKey(match.teamId, match.id),
                status: 'uploaded',
            },
        });

        return new MatchResponseDto(updatedMatch);
    }

    async getStatus(matchId: string): Promise<MatchStatusResponseDto> {
        const match = await this.prisma.read.match.findFirst({
            where: {
                id: matchId,
                deletedAt: null
            },
            select: {
                id: true,
                status: true,
                errorMessage: true
            }
        });

        if (!match) {
            throw new NotFoundException('Match not found.');
        }

        return new MatchStatusResponseDto({
            matchId: match.id,
            status: match.status,
            errorMessage: match.errorMessage,
            progressPercent: null
        });
    }

    async remove(matchId: string): Promise<void> {
        const match = await this.prisma.write.match.findFirst({
            where: {
                id: matchId,
                deletedAt: null,
            },
        });

        if (!match) 
            throw new NotFoundException('Match not found.');

        await this.prisma.write.match.update({
            where: { id: matchId },
            data: {
                deletedAt: new Date(),
            },
        });
    }

    private validateUploadRequest(dto: UploadUrlRequestDto): void {
        if (!MatchesService.ALLOWED_UPLOAD_CONTENT_TYPES.includes(dto.contentType)) {
            throw new BadRequestException({
                code: 'INVALID_FILE_TYPE',
                message: 'Only video/mp4 and video/quicktime are allowed',
            });
        }

        if (dto.fileSizeBytes > this.maxUploadSizeBytes) {
            throw new BadRequestException({
                code: 'FILE_TOO_LARGE',
                message: `File size must not exceed ${this.maxUploadSizeBytes} bytes`,
            });
        }
    }

    private buildRawVideoKey(teamId: string, matchId: string): string {
        return `${teamId}/${matchId}/original.mp4`;
    }
}