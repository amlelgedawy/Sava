import { Controller, Get, Param } from '@nestjs/common';
import { EventsService } from './events.service';

@Controller('events')
export class EventsController {
  constructor(private readonly eventService: EventsService) {}

  @Get('patient/:patientId')
  async getPatientsEvents(@Param('patientId') patientId: string) {
    return this.eventService.getPatientEvents(patientId);
  }
}
