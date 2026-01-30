import { IsEnum, IsString, IsNumber, Max, Min } from 'class-validator';

export class CreateAlertDto {
  patientId: string;
  caregiverId: string;
  type: string;
  severity?: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  confidence?: number;
  payload?: Record<string, any>;
  cooldown?: number; //ms
}
