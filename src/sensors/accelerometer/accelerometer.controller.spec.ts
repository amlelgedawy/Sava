import { Test, TestingModule } from '@nestjs/testing';
import { AccelerometerController } from './accelerometer.controller';

describe('AccelerometerController', () => {
  let controller: AccelerometerController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [AccelerometerController],
    }).compile();

    controller = module.get<AccelerometerController>(AccelerometerController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
