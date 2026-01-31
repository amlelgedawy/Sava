import {
  Controller,
  Body,
  Post,
  UploadedFile,
  UseInterceptors,
  Get
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { CameraService } from './camera.service';
import { IngestFrameDto } from './dto/ingest-frame.dto';

@Controller('camera')
export class CameraController {
  constructor(private readonly cameraService: CameraService) {}

  @Get('ping')
  ping() {
    return { ok: true };
  }
  @Post('frame')
  @UseInterceptors(FileInterceptor('frame'))
   ingestFrame(
    
    @UploadedFile() file: Express.Multer.File,
    @Body() dto: IngestFrameDto,
  ) {
    return this.cameraService.ingestFrame(file, dto);
    console.log('📸 ingestFrame hit', {
    hasFile: !!file,
    patientId: dto?.patientId,
  });
  }
}
