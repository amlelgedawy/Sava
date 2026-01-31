import { Module } from '@nestjs/common';
import { DetectModule } from './detect/detect.module';

@Module({
  imports: [DetectModule],
})
export class AppModule {}