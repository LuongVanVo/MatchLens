export default () => ({
    app: {
        nodeEnv: process.env.NODE_ENV ?? 'development',
        port: Number(process.env.PORT ?? 3000),
        apiPrefix: process.env.API_PREFIX ?? 'v1',
        logLevel: process.env.LOG_LEVEL ?? 'info',
    },
    database: {
        masterUrl: process.env.DATABASE_URL_MASTER,
        replicaUrl: process.env.DATABASE_URL_REPLICA,
    },
    aws: {
        region: process.env.AWS_REGION,
        rawVideosBucket: process.env.S3_RAW_VIDEOS_BUCKET,
        uploadUrlExpiresInSeconds: Number(process.env.UPLOAD_URL_EXPIRES_IN_SECONDS ?? 900),
    },
    auth: {
        accessTokenExpiresIn: process.env.JWT_ACCESS_TOKEN_EXPIRES_IN,
        refreshTokenExpiresIn: process.env.JWT_REFRESH_TOKEN_EXPIRES_IN,
        jwtKeypairSecretName: process.env.JWT_KEYPAIR_SECRET_NAME,
        jwtPrivateKeyPath: process.env.JWT_PRIVATE_KEY_PATH,
        jwtPublicKeyPath: process.env.JWT_PUBLIC_KEY_PATH,
    },
    upload: {
        maxUploadSizeBytes: Number(process.env.MAX_UPLOAD_SIZE_BYTES ?? 2147483648),
        rateLimitTtlSeconds: Number(process.env.UPLOAD_RATE_LIMIT_TTL_SECONDS ?? 60),
        rateLimitLimit: Number(process.env.UPLOAD_RATE_LIMIT_LIMIT ?? 10),
    },
    throttle: {
        ttl: Number(process.env.THROTTLE_TTL ?? 60),
        limit: Number(process.env.THROTTLE_LIMIT ?? 30),
    },
});