import { Exclude, Expose } from "class-transformer";

@Exclude()
export class TeamListItemDto {
    @Expose({ name: 'team_id' })
    id: string;

    @Expose()
    name: string;

    @Expose({ name: 'created_at' })
    createdAt: Date;

    constructor(partial: Partial<TeamListItemDto>) {
        Object.assign(this, partial);
  }
}