import { IsEmail, IsString, MaxLength, MinLength } from 'class-validator';
import { Expose } from 'class-transformer';

export class RegisterDto {
    @IsEmail()
    email!: string;

    @IsString()
    @MinLength(8)
    @MaxLength(255)
    password!: string;

    @Expose({ name: 'full_name' })
    @IsString()
    @MinLength(1)
    @MaxLength(255)
    fullName!: string;
}