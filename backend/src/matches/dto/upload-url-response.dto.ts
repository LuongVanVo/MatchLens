import { Exclude, Expose } from "class-transformer";

@Exclude()
export class UploadUrlResponseDto {
    @Expose({ name: 'upload_url' })
    uploadUrl: string;

    @Expose({ name: 's3_key' })
    s3Key: string;

    @Expose({ name: 'expires_in' })
    expiresIn: number;

    constructor(partial: Partial<UploadUrlResponseDto>) {
        Object.assign(this, partial);
    }
}