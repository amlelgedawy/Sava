import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventsController } from './events.controller';
import { EventsService } from './events.service';
import { FallEvent, FallEventSchema } from './fall-event.schema';
import { AlertsModule } from 'src/alerts/alerts.module';
import { UserModule } from 'src/users/users.module';


@Module({
  imports: [
    MongooseModule.forFeature([
      { name: FallEvent.name, schema: FallEventSchema },
    ]),
    AlertsModule,
    UserModule,
  ],
  controllers: [EventsController],
  providers: [EventsService],
  exports: [EventsService],
})
export class EventsModule {}
