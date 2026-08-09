import { Response } from 'express';

const accessTokenMaxAgeMs = 30 * 60 * 1000;
const refreshTokenMaxAgeMs = 7 * 24 * 60 * 60 * 1000;

const baseCookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'lax' as const,
  path: '/',
};

export function setAuthCookies(
  response: Response,
  accessToken: string,
  refreshToken: string,
): void {
  response.cookie('access_token', accessToken, {
    ...baseCookieOptions,
    maxAge: accessTokenMaxAgeMs,
  });

  response.cookie('refresh_token', refreshToken, {
    ...baseCookieOptions,
    maxAge: refreshTokenMaxAgeMs,
  });
}

export function clearAuthCookies(response: Response): void {
  response.clearCookie('access_token', baseCookieOptions);
  response.clearCookie('refresh_token', baseCookieOptions);
}