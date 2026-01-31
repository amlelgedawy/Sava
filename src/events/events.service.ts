import { forwardRef, Inject, Injectable, Logger } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { Event, EventDocument, EventType } from './fall-event.schema';
import { AlertsService } from 'src/alerts/alerts.service';
import { UserService } from 'src/users/users.service';
import { UserRole } from 'src/users/user.schema';
import { CreateEventDto } from './dto/create-event.dto';

@Injectable()
export class EventsService {
  private readonly logger = new Logger(EventsService.name);

  constructor(
    @InjectModel(Event.name)
    private eventModel: Model<EventDocument>,
    @Inject(forwardRef(() => AlertsService))
    private readonly alertsService: AlertsService,
    private readonly usersService: UserService,
  ) {}

  async handleEvent(dto: CreateEventDto) {
    const event = await this.eventModel.create(dto);

    switch (dto.type) {
      case EventType.FALL:
        await this.handleFall(event);
        break;

      case EventType.FACE:
        await this.handleFace(event);
        break;

      case EventType.OBJECT:
        await this.handleObject(event);
        break;
    }
    return { success: true, event };
  }
  //   FALL EVENT
  private async handleFall(event: Event) {
    const patient = await this.usersService.findById(event.patientId);
    if (!patient || patient.role !== UserRole.PATIENT) {
      this.logger.warn(`Invalid patiemt: ${event.patientId}`);
      return;
    }

    if (!patient.assignedCaregivers?.length) {
      this.logger.warn(`No caregivers assigned to patient ${event.patientId}`);
      return;
    }

    for (const caregiver of patient.assignedCaregivers) {
      await this.alertsService.createGenericAlert({
        patientId: event.patientId,
        caregiverId: caregiver.toString(),
        type: 'FALL',
        confidence: event.confidence ?? 0,
      });

      console.log('ALERT CREATED FOR CAREGIVER:', caregiver.toString());
    }
  }

  // FACE EVENT

  private async handleFace(event: Event) {
    const { recognized } = event.payload || {};

    if (!recognized && (event.confidence ?? 0) >= 0.8) {
      const patient = await this.usersService.findById(event.patientId);
      if (!patient?.assignedCaregivers?.length) return;

      for (const caregiver of patient.assignedCaregivers) {
        await this.alertsService.createGenericAlert({
          patientId: event.patientId,
          caregiverId: caregiver.toString(),
          type: 'unknown_face',
          payload: event.payload,
          cooldown: 120_000, // 2 minutes
        });
      }
    }
  }

  // OBJECT EVENT

  private async handleObject(event: Event) {
    const { object } = event.payload || {};
    const confidence = event.confidence ?? 0;

    if (!object || confidence < 0.8) return;

    const dangerousObject = ['knife', 'scissors'];
    if (!dangerousObject.includes(object)) return;

    const severity =
      object === 'knife'
        ? 'CRITICAL'
        : object === 'scissors'
          ? 'MEDIUM'
          : 'HIGH';

    const patient = await this.usersService.findById(event.patientId);
    if (!patient?.assignedCaregivers?.length) return;

    for (const caregiver of patient.assignedCaregivers) {
      await this.alertsService.createGenericAlert({
        patientId: event.patientId,
        caregiverId: caregiver.toString(),
        type: 'dangerous_object',
        payload: event.payload,
        severity,
        cooldown: 300_000, // 5 min
      });
    }
  }

  // async createFallEvent(fallEventData: {
  //   patientId: string;
  //   confidence: number;
  // }) {
  //   const event = await this.fallEventModel.create({
  //     patientId: fallEventData.patientId,
  //     confidence: fallEventData.confidence,
  //   });

  //

  //
  //   if (
  //     !patient.assignedCaregivers ||
  //     patient.assignedCaregivers.length === 0
  //   ) {
  //     console.warn(
  //       'no catregiver assigned to patient',
  //       fallEventData.patientId,
  //     );
  //     return event;
  //   }
  //
  //   return {
  //     message: 'fall event  created and alert sent',
  //     event,
  //   };
  // }

  async getPatientEvents(patientId: string) {
    return this.eventModel.find({ patientId }).sort({ timestamp: -1 });
  }
}
