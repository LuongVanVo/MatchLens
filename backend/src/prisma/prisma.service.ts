import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  public readonly write: PrismaClient;
  public readonly read: PrismaClient;

  constructor(private readonly configService: ConfigService) {
    const masterUrl = this.configService.get<string>('database.masterUrl');
    const replicaUrl = this.configService.get<string>('database.replicaUrl');

    this.write = new PrismaClient({
      datasources: {
        db: {
          url: masterUrl,
        },
      },
    });

    this.read = new PrismaClient({
      datasources: {
        db: {
          url: replicaUrl,
        },
      },
    });
  }

  async onModuleInit(): Promise<void> {
    await this.write.$connect();
    await this.read.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.write.$disconnect();
    await this.read.$disconnect();
  }
}