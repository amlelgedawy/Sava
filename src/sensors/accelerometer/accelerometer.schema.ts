import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { Document } from 'mongoose';

export type AccelerometerDocument = Accelerometer & Document;

@Schema({ timestamps: true })
export class Accelerometer {
  @Prop({ required: true })
  patientId: string;

  @Prop({ required: true })
  x: number;

  @Prop({ required: true })
  y: number;

  @Prop({ required: true })
  z: number;

  @Prop({ required: true })
  fallDetected: boolean;
}

export const AccelerometerSchema = SchemaFactory.createForClass(Accelerometer);
