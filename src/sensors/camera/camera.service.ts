import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { EventsService } from 'src/events/events.service';
import { HttpService } from '@nestjs/axios';
import { ConfigService } from '@nestjs/config';
import { IngestFrameDto } from './dto/ingest-frame.dto';
import { firstValueFrom } from 'rxjs';
import FormData from 'form-data';
import { AiResponse } from './types/ai-response.type';

@Injectable()
export class CameraService {
  private readonly logger = new Logger(CameraService.name);

  constructor(
    private readonly hhtp: HttpService,
    private readonly configService: ConfigService,
    private readonly eventsService: EventsService,
  ) {}

  async ingestFrame(file: Express.Multer.File, dto: IngestFrameDto) {
    console.log('📸 ingestFrame hit', {
      hasFile: !!file,
      patientId: dto?.patientId,
      mimetype: file?.mimetype,
      size: file?.size,
    });

    if (!file) throw new BadRequestException('frame efile is required');
    const aiUrl = this.configService.get<string>('AI_SERVICE_URL');
    if (!aiUrl) throw new Error('AI_SERVICE_URL is not configured');

    //send form to ai
    const form = new FormData();
    form.append('frame', file.buffer, {
      filename: file.originalname || 'frame.jpg',
      contentType: file.mimetype,
    });
    form.append('patientId', dto.patientId);
    const aiEndpoint = this.configService.get<string>('AI_FRAME_ENDPOINT');
    const resp = await firstValueFrom(
      this.hhtp.post<AiResponse>(`${aiUrl}${aiEndpoint}`, form, {
        headers: form.getHeaders(),
        timeout: 15000,
      }),
    );
    const ai = resp.data;
    console.log(' AI RESPONSE:', JSON.stringify(ai, null, 2));

    if (!ai?.events || !Array.isArray(ai.events)) {
      this.logger.warn(`'AI response missing events array`);
      return { success: false, createdEvents: 0, alertsTriggered: 0 };
    }

    // ai to events
    let created = 0;
    for (const e of ai.events) {
      await this.eventsService.handleEvent({
        patientId: dto.patientId,
        type: e.type,
        confidence: e.confidence,
        payload: {
          ...(e.payload ?? {}),
          source: dto.source ?? 'camera',
          frameMeta: {
            mime: file.mimetype,
            size: file.size,
            name: file.originalname,
          },
        },
      });
      created++;
    }
    return { success: true, createdEvents: created };
  }
}
