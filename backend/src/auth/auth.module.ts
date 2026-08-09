import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { loadJwtKey } from './utils/jwt-keypair.loader';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { RefreshTokenService } from './refresh-token.service';
import { JwtStrategy } from './strategies/jwt.strategy';

@Module({
  imports: [
    ConfigModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const privateKeyPath = configService.getOrThrow<string>('auth.jwtPrivateKeyPath');
        const privateKey = loadJwtKey(privateKeyPath);
        const expiresIn = configService.getOrThrow<string>('auth.accessTokenExpiresIn');

        return {
          privateKey,
          signOptions: {
            algorithm: 'RS256',
            expiresIn: expiresIn as any,
          }
        }
      }
    })
  ],
  controllers: [AuthController],
  providers: [AuthService, RefreshTokenService, JwtStrategy],
  exports: [AuthService]
})

export class AuthModule {}
