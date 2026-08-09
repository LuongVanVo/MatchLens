import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { RefreshTokenService } from './refresh-token.service';
import { RegisterDto } from './dto/register.dto';
import * as bcrypt from 'bcrypt';
import { LoginDto } from './dto/login.dto';
import { JwtPayload } from './interfaces/jwt-payload.interface';
import ms from 'ms';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly refreshTokenService: RefreshTokenService,
  ) {}

  async register(dto: RegisterDto) {
    const existingUser = await this.prisma.write.user.findFirst({
      where: {
        email: dto.email,
        deletedAt: null,
      },
    });

    if (existingUser) {
      throw new ConflictException({
        code: 'EMAIL_ALREADY_EXISTS',
        message: 'Email already exists',
      });
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);

    const user = await this.prisma.write.user.create({
      data: {
        email: dto.email,
        passwordHash,
        fullName: dto.fullName,
      },
    });

    const tokens = await this.issueTokenPair({
      id: user.id,
      email: user.email,
      role: user.role,
    });

    return {
      user_id: user.id,
      email: user.email,
      full_name: user.fullName,
      expires_in: tokens.expires_in,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
    };
  }

  async login(dto: LoginDto) {
    const user = await this.prisma.write.user.findFirst({
      where: {
        email: dto.email,
        deletedAt: null,
      },
    });

    if (!user) {
      throw new UnauthorizedException({
        code: 'INVALID_CREDENTIALS',
        message: 'Invalid email or password',
      });
    }

    const passwordMatched = await bcrypt.compare(dto.password, user.passwordHash);

    if (!passwordMatched) {
      throw new UnauthorizedException({
        code: 'INVALID_CREDENTIALS',
        message: 'Invalid email or password',
      });
    }

    const tokens = await this.issueTokenPair({
      id: user.id,
      email: user.email,
      role: user.role,
    });

    return {
      user_id: user.id,
      email: user.email,
      full_name: user.fullName,
      expires_in: tokens.expires_in,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
    };
  }

  async refresh(refreshToken: string) {
    const storedToken = await this.refreshTokenService.findActiveToken(refreshToken);

    if (!storedToken) {
      throw new UnauthorizedException({
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh token is invalid',
      });
    }

    const user = await this.prisma.write.user.findFirst({
      where: {
        id: storedToken.userId,
        deletedAt: null,
      },
    });

    if (!user) {
      throw new UnauthorizedException({
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh token is invalid',
      });
    }

    await this.refreshTokenService.revokeByRawToken(refreshToken);

    const tokens = await this.issueTokenPair({
      id: user.id,
      email: user.email,
      role: user.role,
    });

    return {
      user_id: user.id,
      email: user.email,
      full_name: user.fullName,
      expires_in: tokens.expires_in,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
    };
  }

  async logout(refreshToken: string) {
    const storedToken = await this.refreshTokenService.findActiveToken(refreshToken);

    if (!storedToken) {
      throw new UnauthorizedException({
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh token is invalid',
      });
    }

    await this.refreshTokenService.revokeByRawToken(refreshToken);

    return {
      message: 'Logout successfully!!!',
    };
  }

  private async issueTokenPair(user: { id: string; email: string; role: string }) {
    const payload: JwtPayload = {
      user_id: user.id,
      email: user.email,
      role: user.role,
    };

    const accessTokenExpiresIn = this.configService.getOrThrow<string>('auth.accessTokenExpiresIn');
    const refreshTokenExpiresIn = this.configService.getOrThrow<string>('auth.refreshTokenExpiresIn');

    const accessToken = await this.jwtService.signAsync(payload);

    const refreshToken = await this.jwtService.signAsync(payload, {
      expiresIn: refreshTokenExpiresIn as any,
    });

    const refreshTokenExpiresAt = new Date(
      Date.now() + ms(refreshTokenExpiresIn as ms.StringValue),
    );

    await this.refreshTokenService.create(user.id, refreshToken, refreshTokenExpiresAt);

    return {
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in: Math.floor(ms(accessTokenExpiresIn as ms.StringValue) / 1000),
    };
  }
}