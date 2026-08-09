import {
  Controller,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

type HealthResponse = {
  status: 'ok';
  db: 'up';
  timestamp: string;
};

type UnhealthyResponse = {
  status: 'degraded';
  db: 'down';
  timestamp: string;
};

@Controller('health')
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  @HttpCode(HttpStatus.OK)
  async check(): Promise<HealthResponse> {
    try {
      await this.prisma.write.$queryRaw`SELECT 1`;
      return {
        status: 'ok',
        db: 'up',
        timestamp: new Date().toISOString(),
      };
    } catch {
      const response: UnhealthyResponse = {
        status: 'degraded',
        db: 'down',
        timestamp: new Date().toISOString(),
      };

      throw new HttpException(response, HttpStatus.SERVICE_UNAVAILABLE);
    }
  }
}