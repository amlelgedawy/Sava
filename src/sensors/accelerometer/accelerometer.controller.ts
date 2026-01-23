import { Controller, Body, Post, Get } from '@nestjs/common';
import { AccelerometerService } from './accelerometer.service';

@Controller('sensors/accelerometer')
export class AccelerometerController {
  constructor(private readonly service: AccelerometerService) {
    console.log('AccelerometerController loaded');
  }

  @Post()
  ingest(@Body() body: { patientId: string; x: number; y: number; z: number }) {
    return this.service.ingest(body);
  }

  @Get('test')
  test() {
    return { message: 'Route is alive!' };
  }
}
