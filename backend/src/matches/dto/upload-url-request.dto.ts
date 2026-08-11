import { Injectable } from "@nestjs/common";
import { Expose } from "class-transformer";
import { IsInt, IsString, Max, MaxLength, Min, MinLength } from "class-validator";

@Injectable()
export class UploadUrlRequestDto {
    @Expose({ name: 'file_name' })
    @IsString()
    @MinLength(1)
    @MaxLength(255)
    fileName!: string;

    @Expose({ name: 'content_type' })
    @IsString()
    @MinLength(1)
    @MaxLength(100)
    contentType!: string;

    @Expose({ name: 'file_size_bytes' })
    @IsInt()
    @Min(1)
    @Max(2147483648)
    fileSizeBytes!: number;
}