import { MatchStatus } from '@prisma/client';
import { Exclude, Expose } from 'class-transformer';

@Exclude()
export class MatchStatusResponseDto {
  @Expose({ name: 'match_id' })
  matchId: string;

  @Expose({ name: 'processing_status' })
  status: MatchStatus;

  @Expose({ name: 'error_message' })
  errorMessage: string | null;

  @Expose({ name: 'progress_percent' })
  progressPercent: number | null;

  constructor(partial: Partial<MatchStatusResponseDto>) {
    Object.assign(this, partial);
  }
}