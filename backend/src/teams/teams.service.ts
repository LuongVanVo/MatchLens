import { Injectable } from "@nestjs/common";
import { PrismaService } from "src/prisma/prisma.service";
import { CreateTeamDto } from "./dto/create-team.dto";
import { TeamResponseDto } from "./dto/team-response.dto";
import { TeamListItemDto } from "./dto/team-list-item.dto";
import { Team } from "@prisma/client";

@Injectable()
export class TeamService {
    constructor(private readonly prisma: PrismaService) {}

    async create(ownerId: string, dto: CreateTeamDto): Promise<TeamResponseDto> {
        const team = await this.prisma.write.team.create({
            data: {
                ownerId,
                name: dto.name
            }
        });

        return new TeamResponseDto(team);
    }

    async findAllByOwner(ownerId: string) {
        const teams = await this.prisma.read.team.findMany({
            where: {
                ownerId,
                deletedAt: null
            },
            orderBy: { createdAt: 'desc' }
        });

        return teams.map((team) => new TeamListItemDto(team));
    }

    toResponseDto(team: Team): TeamResponseDto {
        return new TeamResponseDto(team);
    }
}