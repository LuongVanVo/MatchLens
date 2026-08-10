import { CanActivate, ExecutionContext, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { Observable } from "rxjs";
import { PrismaService } from "src/prisma/prisma.service";

@Injectable()
export class TeamOwnershipGuard implements CanActivate {
    constructor(private readonly prisma: PrismaService) {}

    async canActivate(context: ExecutionContext): Promise<boolean> {
        const request = context.switchToHttp().getRequest();
        const userId = request.user.id;
        const teamId = request.params.team_id;

        const team = await this.prisma.write.team.findFirst({
            where: { id: teamId, deletedAt: null }
        });

        if (!team) {
            throw new NotFoundException("Team not found!");
        }

        if (team.ownerId !== userId && request.user.role !== 'admin') {
            throw new ForbiddenException("You do not have access to this resource!");
        }

        request.team = team;

        return true;
    }
}