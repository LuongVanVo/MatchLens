import { Exclude, Expose } from 'class-transformer';

@Exclude()
export class PlayerListItemDto {
  @Expose({ name: 'player_id' })
  id: string;

  @Expose({ name: 'full_name' })
  fullName: string;

  @Expose({ name: 'jersey_number' })
  jerseyNumber: number | null;

  @Expose()
  position: string | null;

  @Expose({ name: 'created_at' })
  createdAt: Date;

  constructor(partial: Partial<PlayerListItemDto>) {
    Object.assign(this, partial);
  }
}