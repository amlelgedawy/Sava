import { Module } from '@nestjs/common';
import  {HttpModule} from '@nestjs/axios';
import { CameraController } from './camera.controller';
import { CameraService } from './camera.service';
import { EventsModule } from 'src/events/events.module';

@Module({
  imports: [HttpModule, EventsModule],
  controllers: [CameraController],
  providers: [CameraService],
  exports: [CameraService],
})
export class CameraModule {}
