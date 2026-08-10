import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "src/prisma/prisma.service";
import { CreatePlayerDto } from "./dto/create-player.dto";
import { Prisma } from "@prisma/client";
import { PlayerResponseDto } from "./dto/player-response.dto";
import { PlayerListItemDto } from "./dto/player-list-item.dto";
import { UpdatePlayerDto } from "./dto/update-player.dto";

@Injectable()
export class PlayersService {
    constructor(private readonly prisma: PrismaService) {}

    async create(teamId: string, dto: CreatePlayerDto): Promise<PlayerResponseDto> {
        try {
            if (dto.jerseyNumber) {
                const isExist = await this.prisma.read.player.findFirst({
                    where: {
                        teamId,
                        jerseyNumber: dto.jerseyNumber,
                        deletedAt: null
                    },
                });

                if (isExist) 
                    throw new ConflictException("Jersey number already exists in this team.");
            }
            
            const player = await this.prisma.write.player.create({
                data: {
                    teamId,
                    fullName: dto.fullName,
                    jerseyNumber: dto.jerseyNumber ?? null,
                    position: dto.position ?? null,
                },
            });

            return new PlayerResponseDto(player);
        } catch (error) {
            this.handleConstraintError(error);
        }
    }

    async findAllByTeam(teamId: string): Promise<PlayerListItemDto[]> {
        const players = await this.prisma.read.player.findMany({
            where: {
                teamId,
                deletedAt: null
            },
            orderBy: [{ jerseyNumber: 'asc' }, { createdAt: 'desc' }]
        });

        return players.map((player) => new PlayerListItemDto(player));
    }

    async update(teamId: string, playerId: string, dto: UpdatePlayerDto): Promise<PlayerResponseDto> {
        const existingPlayer = await this.prisma.write.player.findFirst({
            where: {
                id: playerId,
                teamId,
                deletedAt: null
            },
        });

        if (!existingPlayer)
            throw new NotFoundException("Player not found!!");
        try {
            const player = await this.prisma.write.player.update({
                where: { id: playerId },
                data: {
                    ...(dto.fullName !== undefined ? { fullName: dto.fullName } : {}),
                    ...(dto.jerseyNumber !== undefined
                        ? { jerseyNumber: dto.jerseyNumber }
                        : {}),
                    ...(dto.position !== undefined ? { position: dto.position } : {}),
                },
            });

            return new PlayerResponseDto(player);
        } catch (error) {
            this.handleConstraintError(error);
        }
    }

    async remove(teamId: string, playerId: string): Promise<void> {
        const existingPlayer = await this.prisma.write.player.findFirst({
            where: {
                id: playerId,
                teamId
            },
        });
        if (!existingPlayer)
            throw new NotFoundException("Player not found!!");

        await this.prisma.write.player.update({
            where: { id: playerId },
            data: {
                deletedAt: new Date(),
            },
        });
    }

    private handleConstraintError(error: unknown): never { // Khai báo với TypeScript rằng hàm này sẽ không bao giờ trả về bất kỳ kết quả nào. Lý do là vì nó sinh ra chỉ để quăng lỗi (throw error) làm ngắt mạch chạy của chương trình.
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
            throw new ConflictException("Jersey number already exists in this team.");
        }

        throw error;
    }
}