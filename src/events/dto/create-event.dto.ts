import { EventType } from '../fall-event.schema';
import { IsEnum, IsOptional, IsString, IsNumber, IsObject } from 'class-validator';


export class CreateEventDto {
  
  @IsString()
  patientId: string;
  @IsEnum(EventType)
  type: EventType;
  @IsOptional()
  @IsNumber()
  confidence?: number;
  @IsOptional()
  @IsObject()
  payload?: any;
}
