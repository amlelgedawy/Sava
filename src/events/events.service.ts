import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { FallEvent, FallEventDocument } from './fall-event.schema';
import { AlertsService } from 'src/alerts/alerts.service';
import { EventsModule } from './events.module';
import { UserService } from 'src/users/users.service';
import { UserRole } from 'src/users/user.schema';

@Injectable()
export class EventsService {
  constructor(
    @InjectModel(FallEvent.name)
    private fallEventModel: Model<FallEventDocument>,

    private readonly alertsService: AlertsService,
    private readonly usersService: UserService,
  ) {}

  async createFallEvent(fallEventData: {
    patientId: string;
    confidence: number;
  }) {
    const event = await this.fallEventModel.create({
      patientId: fallEventData.patientId,
      confidence: fallEventData.confidence,
    });

    const patient = await this.usersService.findById(fallEventData.patientId);

    if (!patient || patient.role !== UserRole.PATIENT) {
      console.warn(
        'no catregiver assigned to patient',
        fallEventData.patientId,
      );
      return event;
    }

    if (
      !patient.assignedCaregivers ||
      patient.assignedCaregivers.length === 0
    ) {
      console.warn('user is not a patient', fallEventData.patientId);
      return event;
    }
    for (const caregiver of patient.assignedCaregivers) {
      await this.alertsService.createFallAlert({
        patientId: fallEventData.patientId,
        caregiverId: caregiver.toString(),
        type: 'FALL',
        confidence: fallEventData.confidence,
      });

      // console.log('ALERT CREATED FOR CAREGIVER:', caregiver.toString());
    }
    return {
      message: 'fall event  created and alert sent',
      event,
    };
  }

  async getPatientEvents(patientId: string) {
    return this.fallEventModel.find({ patientId }).sort({ timestamp: -1 });
  }
}
