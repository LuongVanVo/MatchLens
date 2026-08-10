import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Post, Put, UseGuards } from "@nestjs/common";
import { PlayersService } from "./players.service";
import { JwtAuthGuard } from "src/common/guards/jwt-auth.guard";
import { TeamOwnershipGuard } from "src/common/guards/team-ownership.guard";
import { CreatePlayerDto } from "./dto/create-player.dto";
import { PlayerResponseDto } from "./dto/player-response.dto";
import { PlayerListItemDto } from "./dto/player-list-item.dto";
import { UpdatePlayerDto } from "./dto/update-player.dto";

@Controller('teams/:team_id/players')
@UseGuards(JwtAuthGuard, TeamOwnershipGuard)
export class PlayersController {
    constructor(private readonly playersService: PlayersService) {}

    @Post()
    async create(
        @Param('team_id') teamId: string,
        @Body() dto: CreatePlayerDto
    ): Promise<PlayerResponseDto> {
        return this.playersService.create(teamId, dto);
    }

    @Get()
    async findAll(
        @Param('team_id') teamId: string
    ): Promise<PlayerListItemDto[]> {
        return this.playersService.findAllByTeam(teamId);
    }

    @Put(':player_id')
    async update(
        @Param('team_id') teamId: string,
        @Param('player_id') playerId: string,
        @Body() dto: UpdatePlayerDto,
    ): Promise<PlayerResponseDto> {
        return this.playersService.update(teamId, playerId, dto);
    }

    @Delete(':player_id')
    @HttpCode(HttpStatus.OK)
    async remove(
        @Param('team_id') teamId: string,
        @Param('player_id') playerId: string,
    ): Promise<null> {
        await this.playersService.remove(teamId, playerId);
        return null;
    }
}