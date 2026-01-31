import { Injectable } from '@nestjs/common';
import axios from 'axios';
import FormData from 'form-data';

@Injectable()
export class DetectService {
  private readonly fastApiUrl = 'http://localhost:8000/detect/';

  async detectDangerousObjects(file: Express.Multer.File): Promise<Buffer> {
    const formData = new FormData();
    formData.append('file', file.buffer, { filename: file.originalname });

    const response = await axios.post(this.fastApiUrl, formData, {
      headers: formData.getHeaders(),
      responseType: 'arraybuffer',
    });

    return Buffer.from(response.data);
  }
}
