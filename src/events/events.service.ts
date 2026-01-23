import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { FallEvent, FallEventDocument } from './fall-event.schema';

@Injectable()
export class EventsService {
  constructor(
    @InjectModel(FallEvent.name)
    private fallEventModel: Model<FallEventDocument>,
  ) {}

  async createFallEvent(fallEventData: {
    patientId: string;
    confidance: number;
  }) {
    return this.fallEventModel.create({
      patientId: fallEventData.patientId,
      confidence: fallEventData.confidance,
    });
  }
  async getPatientEvents(patientId: string){
    return this.fallEventModel.find({patientId}).sort({timestamp:-1});
  }
}
