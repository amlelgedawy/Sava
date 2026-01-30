import { EventType } from '../fall-event.schema';
import { IsEnum, IsOptional, IsString, IsNumber, IsObject } from 'class-validator';
import type { EventPayload } from '../event-payload';

export class CreateEventDto {
  
  @IsString()
  patientId: string;
  @IsEnum(EventType)
  type: EventType;
  @IsOptional()
  @IsNumber()
  confidence?: number; // 0 to 1
  @IsOptional()
  @IsObject()
  payload?: EventPayload;

}
