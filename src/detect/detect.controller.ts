import { Controller, Post, UploadedFile, UseInterceptors, Res } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { DetectService } from './detect.service';
import type { Response } from 'express';

@Controller('detect')
export class DetectController {
  constructor(private readonly detectService: DetectService) {}

  @Post()
  @UseInterceptors(FileInterceptor('file'))
  async detect(@UploadedFile() file: Express.Multer.File, @Res() res: Response) {
    const resultBuffer = await this.detectService.detectDangerousObjects(file);
    res.setHeader('Content-Type', 'image/jpeg');
    res.send(resultBuffer);
  }
}
