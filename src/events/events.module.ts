import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventsController } from './events.controller';
import { EventsService } from './events.service';
import { FallEvent, FallEventSchema } from './fall-event.schema';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: FallEvent.name, schema: FallEventSchema },
    ]),
  ],
  controllers: [EventsController],
  providers: [EventsService],
  exports: [EventsService],
})
export class EventsModule {}
