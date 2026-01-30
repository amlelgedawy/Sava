import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { Document } from 'mongoose';

export enum EventType {
  FALL = 'FALL',
  FACE = 'FACE',
  OBJECT = 'OBJECT',
}

@Schema({ timestamps: false })
export class Event extends Document {
  @Prop({ required: true })
  patientId: string;

  @Prop({ required: true, enum: EventType })
  type: EventType;

  @Prop()
  confidence?: number;

  @Prop({ type: Object })
  payload?: any;

  // @Prop({ required: true, min:0, max:1 })
  // confidence: number;

  // @Prop({ default: 'HIGH' })
  // severity: string;

  // @Prop({ default: Date.now })
  // timestamp: Date
}
export const EventSchema = SchemaFactory.createForClass(Event);
export type EventDocument = Event & Document;
