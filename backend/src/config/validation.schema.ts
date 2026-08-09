import * as Joi from 'joi';

export const validationSchema = Joi.object({
    NODE_ENV: Joi.string()
        .valid('development', 'test', 'staging', 'production')
        .default('development'),
    
    PORT: Joi.number().port().default(3000),
    API_PREFIX: Joi.string().default('v1'),
    LOG_LEVEL: Joi.string()
        .valid('fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent')
        .default('info'),
    
    DATABASE_URL_MASTER: Joi.string().uri({ scheme: ['postgresql', 'postgres'] }).required(),
    DATABASE_URL_REPLICA: Joi.string().uri({ scheme: ['postgresql', 'postgres'] }).required(),

    AWS_REGION: Joi.string().required(),

    JWT_ACCESS_TOKEN_EXPIRES_IN: Joi.string().required(),
    JWT_REFRESH_TOKEN_EXPIRES_IN: Joi.string().required(),
    JWT_KEYPAIR_SECRET_NAME: Joi.string().required(),
    JWT_PRIVATE_KEY_PATH: Joi.string().required(),
    JWT_PUBLIC_KEY_PATH: Joi.string().required(),

    THROTTLE_TTL: Joi.number().integer().positive().default(60),
    THROTTLE_LIMIT: Joi.number().integer().positive().default(30),
});