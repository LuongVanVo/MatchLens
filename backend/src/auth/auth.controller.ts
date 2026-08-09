import { Body, Controller, Post, Req, Res, UseGuards, UnauthorizedException } from '@nestjs/common';
import type { Request, Response } from 'express';
import { AuthService } from './auth.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { JwtAuthGuard } from 'src/common/guards/jwt-auth.guard';
import { setAuthCookies, clearAuthCookies } from './utils/auth-cookie.util';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  async register(
    @Body() dto: RegisterDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result = await this.authService.register(dto);

    setAuthCookies(res, result.access_token, result.refresh_token);

    return {
      user_id: result.user_id,
      email: result.email,
      full_name: result.full_name,
      expires_in: result.expires_in,
    };
  }

  @Post('login')
  async login(
    @Body() dto: LoginDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result = await this.authService.login(dto);

    setAuthCookies(res, result.access_token, result.refresh_token);

    return {
      user_id: result.user_id,
      email: result.email,
      full_name: result.full_name,
      expires_in: result.expires_in,
    };
  }

  @Post('refresh')
  async refresh(
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const refreshToken = req.cookies?.refresh_token;

    if (!refreshToken) {
      throw new UnauthorizedException({
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh token is invalid',
      });
    }

    const result = await this.authService.refresh(refreshToken);

    setAuthCookies(res, result.access_token, result.refresh_token);

    return {
      user_id: result.user_id,
      email: result.email,
      full_name: result.full_name,
      expires_in: result.expires_in,
    };
  }

  @UseGuards(JwtAuthGuard)
  @Post('logout')
  async logout(
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const refreshToken = req.cookies?.refresh_token;

    if (!refreshToken) {
      throw new UnauthorizedException({
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh token is invalid',
      });
    }

    await this.authService.logout(refreshToken);
    clearAuthCookies(res);

    return {
      message: 'Logout successfully!!!',
    };
  }
}