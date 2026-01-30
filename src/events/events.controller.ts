import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { EventsService } from './events.service';
import { CreateEventDto } from './dto/create-event.dto';

@Controller('events')
export class EventsController {
  constructor(private readonly eventService: EventsService) {}

@Post()
async ingestEvent(@Body() dto: CreateEventDto){
  return this.eventService.handleEvent(dto);
}

  @Get('patient/:patientId')
  async getPatientsEvents(@Param('patientId') patientId: string) {
    return this.eventService.getPatientEvents(patientId);
  }

}
