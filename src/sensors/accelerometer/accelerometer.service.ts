import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { Accelerometer, AccelerometerDocument } from './accelerometer.schema';
import { EventsService } from 'src/events/events.service';

@Injectable()
export class AccelerometerService {
  constructor(
    @InjectModel(Accelerometer.name)
    private model: Model<AccelerometerDocument>,
    private readonly eventsService: EventsService,
  ) {}

  async ingest(data: { patientId: string;  x: number; y: number; z: number }) {
    const magnitude = Math.sqrt(
      data.x * data.x + data.y * data.y + data.z * data.z,
    );
    const fallDetected = magnitude > 25;

    await this.model.create({
      patientId: data.patientId,
      x: data.x,
      y: data.y,
      z: data.z,
      fallDetected,
    });

    if (fallDetected) {
      await this.eventsService.createFallEvent({
        patientId: data.patientId,
        confidence: Math.min(magnitude / 50, 1),
      });
    }

    return {
      recieved: true,
      fallDetected,
    };
  }
}
