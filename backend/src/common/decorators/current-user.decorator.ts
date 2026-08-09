import { createParamDecorator, ExecutionContext } from "@nestjs/common";

export type CurrentUserType = {
    id: string;
    email: string;
    role: string;
}

export const CurrentUser = createParamDecorator(
    (_data: unknown, ctx: ExecutionContext): CurrentUserType => {
        const request = ctx.switchToHttp().getRequest();
        return request.user;
    }
)