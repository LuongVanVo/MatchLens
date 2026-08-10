import { Exclude, Expose } from "class-transformer";

@Exclude()
export class TeamResponseDto {
    @Expose({ name: "team_id" })
    id: string;

    @Expose()
    name: string;

    @Expose({ name: 'owner_id' })
    ownerId: string;

    @Expose({ name: 'created_at' })
    createdAt: Date;

    constructor(parital: Partial<TeamResponseDto>) {
        Object.assign(this, parital);
    }
}