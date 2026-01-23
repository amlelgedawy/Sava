import { Prop, Schema, SchemaFactory } from "@nestjs/mongoose";
import { Document } from "mongoose";

export type FallEventDocument = FallEvent & Document;

@Schema({ timestamps: false })
export class FallEvent {
    @Prop({ required: true })
    patientId: string;

    @Prop({ default: 'FALL_DETECTED' })
    eventType: string;

    @Prop({ default: 'ACCELEROMETER' })
    source: string;

    @Prop({ required: true, min:0, max:1 })
    confidence: number;

    @Prop({ default: 'HIGH' })
    severity: string;

    @Prop({ default: Date.now })
    timestamp: Date
}
export const FallEventSchema = SchemaFactory.createForClass(FallEvent);