import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { MatchOwnershipGuard } from '../common/guards/match-ownership.guard';
import { TeamOwnershipGuard } from '../common/guards/team-ownership.guard';
import { CreateMatchDto } from './dto/create-match.dto';
import { MatchListItemDto } from './dto/match-list-item.dto';
import { MatchResponseDto } from './dto/match-response.dto';
import { MatchesService } from './matches.service';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { UploadUrlRequestDto } from './dto/upload-url-request.dto';
import type { Request } from 'express';
import { UploadUrlResponseDto } from './dto/upload-url-response.dto';
import { Match } from '@prisma/client';
import { Throttle } from '@nestjs/throttler';
import { ConfirmUploadDto } from './dto/confirm-upload.dto';
import { MatchStatusResponseDto } from './dto/match-status-response.dto';

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

  @Post('matches/:match_id/upload-url')
  @UseGuards(MatchOwnershipGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  async createUploadUrl(
    @Param('match_id') matchId: string,
    @Body() dto: UploadUrlRequestDto,
    @Req() req: Request,
  ): Promise<UploadUrlResponseDto> {
    const match = (req as Request & { match: Pick<Match, 'id' | 'teamId' | 'status'> }).match;

    return this.matchesService.createUploadUrl(matchId, match.teamId, match.status, dto);
  }

  @Post('matches/:match_id/confirm-upload')
  @UseGuards(MatchOwnershipGuard)
  async confirmUpload(
    @Param('match_id') matchId: string,
    @Body() _dto: ConfirmUploadDto,
  ): Promise<MatchResponseDto> {
    return this.matchesService.confirmUpload(matchId);
  }

  @Get('matches/:match_id/status')
  @UseGuards(MatchOwnershipGuard)
  async getStatus(
    @Param('match_id') matchId: string,
  ): Promise<MatchStatusResponseDto> {
    return this.matchesService.getStatus(matchId);
  }

  @Delete('matches/:match_id')
  @HttpCode(HttpStatus.OK)
  @UseGuards(MatchOwnershipGuard)
  async remove(@Param('match_id') matchId: string): Promise<null> {
    await this.matchesService.remove(matchId);
    return null;
  }
}