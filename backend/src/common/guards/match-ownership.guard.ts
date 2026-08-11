import { CanActivate, ExecutionContext, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { Observable } from "rxjs";
import { PrismaService } from "src/prisma/prisma.service";

@Injectable()
export class MatchOwnershipGuard implements CanActivate {
    constructor(private readonly prisma: PrismaService) {}

    async canActivate(context: ExecutionContext): Promise<boolean> {
        const request = context.switchToHttp().getRequest();
        const userId = request.user.id;
        const matchId = request.params.match_id;

        const match = await this.prisma.write.match.findFirst({
            where: { id: matchId, deletedAt: null },
            select: { id: true, team: { select: { ownerId: true } } },
        });

        if (!match) {
            throw new NotFoundException('Match not found');
        }

        if (match.team.ownerId !== userId && request.user.role !== 'admin') {
            throw new ForbiddenException('You do not have access to this resource');
        }

        request.match = match;

        return true;
    }
}