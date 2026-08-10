import { Module } from "@nestjs/common";
import { TeamsController } from "./teams.controller";
import { TeamService } from "./teams.service";
import { TeamOwnershipGuard } from "src/common/guards/team-ownership.guard";

@Module({
    imports: [],
    controllers: [TeamsController],
    providers: [TeamService, TeamOwnershipGuard],
    exports: [],
})

export class TeamsModule {}