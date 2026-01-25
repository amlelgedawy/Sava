import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { Document } from 'mongoose';

export type AlertDocument = Alert & Document;

@Schema({ timestamps: true })
export class Alert {
  @Prop({ required: true })
  patientId: string;

  @Prop({ required: true })
  caregiverId: string;

  @Prop({
    enum: ['FALL', 'WANDERING'],
    required: true,
  })
  type: string;
  @Prop({ min: 0, max: 1 })
  confidance: number;

  @Prop({
    enum: ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'],

    default: 'HIGH',
  })
  severity: string;
  @Prop({ default: false })
  acknowledged: boolean;
}

export const AlertSchema = SchemaFactory.createForClass(Alert);
AlertSchema.index({ patientId: 1, caregiverId: 1, type: 1, createdAt: 1 });
