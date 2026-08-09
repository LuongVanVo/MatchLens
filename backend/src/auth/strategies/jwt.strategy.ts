import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { Strategy } from 'passport-jwt';
import { loadJwtKey } from '../utils/jwt-keypair.loader';
import { JwtPayload } from '../interfaces/jwt-payload.interface';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly configService: ConfigService) {
    const publicKeyPath = configService.getOrThrow<string>('auth.jwtPublicKeyPath');
    const publicKey = loadJwtKey(publicKeyPath);

    super({
      jwtFromRequest: (request) => request?.cookies?.access_token ?? null,
      ignoreExpiration: false,
      secretOrKey: publicKey,
      algorithms: ['RS256'],
    });
  }

  async validate(payload: JwtPayload) {
    return {
      id: payload.user_id,
      email: payload.email,
      role: payload.role,
    };
  }
}