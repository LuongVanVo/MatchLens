import { Expose } from "class-transformer";
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min, MinLength } from "class-validator";

export class CreatePlayerDto {
    @Expose({ name: "full_name" })
    @IsString()
    @MinLength(1)
    @MaxLength(255)
    fullName!: string;    

    @Expose({ name: 'jersey_number' })
    @IsOptional()
    @IsInt()
    @Min(1)
    @Max(99)
    jerseyNumber?: number;

    @Expose()
    @IsOptional()
    @IsString()
    @IsIn(['goalkeeper', 'defender', 'midfielder', 'forward'])
    position?: string;
}