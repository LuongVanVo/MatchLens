import { Module } from "@nestjs/common";
import { MatchesController } from "./matches.controller";
import { MatchesService } from "./matches.service";
import { MatchOwnershipGuard } from "src/common/guards/match-ownership.guard";
import { AwsModule } from "src/aws/aws.module";

@Module({
    imports: [AwsModule],
    controllers: [MatchesController],
    providers: [MatchesService, MatchOwnershipGuard],
})

export class MatchesModule {}