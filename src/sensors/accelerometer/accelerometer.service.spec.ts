import { Test, TestingModule } from '@nestjs/testing';
import { AccelerometerService } from './accelerometer.service';

describe('AccelerometerService', () => {
  let service: AccelerometerService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [AccelerometerService],
    }).compile();

    service = module.get<AccelerometerService>(AccelerometerService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
