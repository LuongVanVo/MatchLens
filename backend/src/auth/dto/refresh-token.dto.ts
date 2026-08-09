import { Expose } from 'class-transformer';
import { IsString, MinLength } from 'class-validator';

export class RefreshTokenDto {
  @Expose({ name: 'refresh_token' })
  @IsString()
  @MinLength(1)
  refreshToken!: string;
}