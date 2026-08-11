import { MatchStatus } from "@prisma/client";
import { Exclude, Expose } from "class-transformer";

@Exclude()
export class MatchResponseDto {
    @Expose({ name: 'match_id' })
    id: string;

    @Expose({ name: 'team_id' })
    teamId: string;

    @Expose({ name: 'opponent_name' })
    opponentName: string;

    @Expose({ name: 'match_date' })
    matchDate: Date;

    @Expose({ name: 'processing_status' })
    status: MatchStatus;

    @Expose({ name: 'video_s3_key' })
    videoS3Key: string | null;

    @Expose({ name: 'created_at' })
    createdAt: Date;

    constructor(partial: Partial<MatchResponseDto>) {
        Object.assign(this, partial);
    }
}