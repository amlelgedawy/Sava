import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { Accelerometer, AccelerometerSchema } from './accelerometer.schema';
import { AccelerometerController } from './accelerometer.controller';
import { AccelerometerService } from './accelerometer.service';
import { EventsModule } from 'src/events/events.module';


@Module({
  imports: [
    MongooseModule.forFeature([
      { name: 'Accelerometer', schema: AccelerometerSchema },
    ]),
    EventsModule,
  ],
  controllers: [AccelerometerController],
  providers: [AccelerometerService],
})
export class AccelerometerModule {}
