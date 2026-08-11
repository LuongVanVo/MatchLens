import { Injectable } from "@nestjs/common";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { ConfigService } from "@nestjs/config";
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';


@Injectable()
export class S3Service {
    private readonly client: S3Client;
    private readonly rawVideosBucket: string;
    private readonly uploadUrlExpiresInSeconds: number;

    constructor(private readonly configService: ConfigService) {
        const region = this.configService.getOrThrow<string>('aws.region');

        this.client = new S3Client({ 
            region, 
            // requestChecksumCalculation: 'WHEN_REQUIRED' 
        });
        this.rawVideosBucket = this.configService.getOrThrow<string>('aws.rawVideosBucket');
        this.uploadUrlExpiresInSeconds = this.configService.getOrThrow<number>('aws.uploadUrlExpiresInSeconds');
    }

    async createPresignedUploadUrl(params: {
        key: string;
        contentType: string;
    }): Promise<{ uploadUrl: string, expiresIn: number }> {
        const command = new PutObjectCommand({
            Bucket: this.rawVideosBucket,
            Key: params.key,
            ContentType: params.contentType
        });

        const uploadUrl = await getSignedUrl(this.client, command, {
            expiresIn: this.uploadUrlExpiresInSeconds,
            // signableHeaders: new Set(['host', 'content-type'])
        });

        return {
            uploadUrl,
            expiresIn: this.uploadUrlExpiresInSeconds,
        };
    }
}