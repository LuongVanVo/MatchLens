import { Body, Controller, Get, Post, Req, UseGuards } from "@nestjs/common";
import type { Request } from "express";
import { JwtAuthGuard } from "src/common/guards/jwt-auth.guard";
import { TeamService } from "./teams.service";
import * as currentUserDecorator from "src/common/decorators/current-user.decorator";
import { CreateTeamDto } from "./dto/create-team.dto";
import { TeamResponseDto } from "./dto/team-response.dto";
import { TeamListItemDto } from "./dto/team-list-item.dto";
import { Team } from "@prisma/client";
import { TeamOwnershipGuard } from "src/common/guards/team-ownership.guard";

@Controller('teams')
@UseGuards(JwtAuthGuard)
export class TeamsController {
    constructor(private readonly teamsService: TeamService) {}

    @Post()
    async create(
        @currentUserDecorator.CurrentUser() user: currentUserDecorator.CurrentUserType,
        @Body() dto: CreateTeamDto,
    ) : Promise<TeamResponseDto> {
        return this.teamsService.create(user.id, dto);
    }

    @Get()
    async findAll(@currentUserDecorator.CurrentUser() user: currentUserDecorator.CurrentUserType): Promise<TeamListItemDto[]> {
        return this.teamsService.findAllByOwner(user.id);
    }

    @UseGuards(TeamOwnershipGuard)
    @Get(":team_id")
    async findOne(@Req() req: Request): Promise<TeamResponseDto> {
        const team = (req as Request & { team: Team }).team;
        return this.teamsService.toResponseDto(team);
    }
}