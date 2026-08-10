import { Exclude, Expose } from "class-transformer";

@Exclude()
export class PlayerResponseDto {
    @Expose({ name: "player_id" })
    id: string;

    @Expose({ name: 'team_id' })
    teamId: string;

    @Expose({ name: 'full_name' })
    fullName: string;

    @Expose({ name: 'jersey_number' })
    jerseyNumber: number | null;

    @Expose()
    position: string | null;

    @Expose({ name: 'created_at' })
    createdAt: Date;

    @Expose({ name: 'updated_at' })
    updatedAt: Date;

    constructor(partial: Partial<PlayerResponseDto>) {
        Object.assign(this, partial);
    }
}