import { IsEnum, IsString, IsNumber, Max, Min } from 'class-validator';
export class CreateAlertDto {
  @IsString()
  patientId: string;

  @IsString()
  caregiverId: string;

  @IsEnum(['FALL', 'WANDERING'])
  type: string;

  @IsNumber()
  @Min(0)
  @Max(1)
  confidence: number;
}
