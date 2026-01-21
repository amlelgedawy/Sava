import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { Document, Types } from 'mongoose';

export enum UserRole {
  CAREGIVER = 'caregiver',
  PATIENT = 'patient',
}

@Schema({ timestamps: true })
export class User extends Document {
  @Prop({ required: true })
  name: string;

  @Prop({ unique: true, sparse: true })
  email?: string;

  @Prop({ required: true, enum: UserRole })
  role: UserRole;

  @Prop({ type: [{ type: Types.ObjectId, ref: 'User' }] })
  assignedPatients?: Types.ObjectId[];

  @Prop({ type: [{ type: Types.ObjectId, ref: 'User' }] })
  assignedCaregivers?: Types.ObjectId[];
}

export const UserSchema = SchemaFactory.createForClass(User);
