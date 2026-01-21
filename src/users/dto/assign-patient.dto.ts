import { IsMongoId } from 'class-validator';

export class AssignPatientDto {
  @IsMongoId()
  caregiverId: string;
  
  @IsMongoId()
  patientId: string;
}
