import { Expose } from "class-transformer";
import { IsDateString, IsString, MaxLength, MinLength } from "class-validator";

export class CreateMatchDto {
    @Expose({ name: 'opponent_name' })
    @IsString()
    @MinLength(1)
    @MaxLength(255)
    opponentName!: string;

    @Expose({ name: 'match_date' })
    @IsDateString()
    matchDate!: string;
}