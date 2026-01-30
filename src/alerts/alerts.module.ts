import { forwardRef, Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { AlertsService } from './alerts.service';
import { AlertsController } from './alerts.controller';
import { Alert, AlertSchema } from './alert.schema';
import { EventsModule } from 'src/events/events.module';

@Module({
  imports:[MongooseModule.forFeature([{name:Alert.name,schema:AlertSchema},
  ]),
  forwardRef(()=> EventsModule),
],
  providers: [AlertsService],
  controllers: [AlertsController],
  exports: [AlertsService],
})
export class AlertsModule {}
