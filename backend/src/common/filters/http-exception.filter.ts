import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from "@nestjs/common";
import { Response } from "express";

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
    catch(exception: unknown, host: ArgumentsHost) {
        const ctx = host.switchToHttp();
        const response = ctx.getResponse<Response>();

        const status = exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;

        const message = exception instanceof HttpException ? exception.getResponse() : "Internal server error";

        // handle information error (if is validation error => return array, if not => return string)
        let errorDetail = message;
        if (typeof message === 'object' && message !== null && 'message' in message) {
            errorDetail = (message as any).message;
        }

        response.status(status).json({
            success: false,
            data: null,
            error: {
                code: status,
                message: errorDetail,
            },
        });
    }
}