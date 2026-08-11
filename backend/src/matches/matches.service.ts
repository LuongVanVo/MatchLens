import { Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "src/prisma/prisma.service";
import { CreateMatchDto } from "./dto/create-match.dto";
import { MatchResponseDto } from "./dto/match-response.dto";
import { MatchListItemDto } from "./dto/match-list-item.dto";

@Injectable()
export class MatchesService {
    constructor(private readonly prisma: PrismaService) {}

    async create(teamId: string, dto: CreateMatchDto): Promise<MatchResponseDto> {
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
}