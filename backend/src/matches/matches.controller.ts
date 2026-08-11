import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { MatchOwnershipGuard } from '../common/guards/match-ownership.guard';
import { TeamOwnershipGuard } from '../common/guards/team-ownership.guard';
import { CreateMatchDto } from './dto/create-match.dto';
import { MatchListItemDto } from './dto/match-list-item.dto';
import { MatchResponseDto } from './dto/match-response.dto';
import { MatchesService } from './matches.service';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

@Controller()
@UseGuards(JwtAuthGuard)
export class MatchesController {
  constructor(private readonly matchesService: MatchesService) {}

  @Post('teams/:team_id/matches')
  @UseGuards(TeamOwnershipGuard)
  async create(
    @Param('team_id') teamId: string,
    @Body() dto: CreateMatchDto,
  ): Promise<MatchResponseDto> {
    return this.matchesService.create(teamId, dto);
  }

  @Get('teams/:team_id/matches')
  @UseGuards(TeamOwnershipGuard)
  async findAll(
    @Param('team_id') teamId: string,
  ): Promise<MatchListItemDto[]> {
    return this.matchesService.findAllByTeam(teamId);
  }

  @Delete('matches/:match_id')
  @HttpCode(HttpStatus.OK)
  @UseGuards(MatchOwnershipGuard)
  async remove(@Param('match_id') matchId: string): Promise<null> {
    await this.matchesService.remove(matchId);
    return null;
  }
}