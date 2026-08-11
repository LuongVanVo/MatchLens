import { Module } from "@nestjs/common";
import { MatchesController } from "./matches.controller";
import { MatchesService } from "./matches.service";
import { MatchOwnershipGuard } from "src/common/guards/match-ownership.guard";

@Module({
    controllers: [MatchesController],
    providers: [MatchesService, MatchOwnershipGuard],
})

export class MatchesModule {}