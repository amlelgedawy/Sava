import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { Alert, AlertDocument } from './alert.schema';
import { CreateAlertDto } from './dto/create-alert.dto';

@Injectable()
export class AlertsService {
  constructor(
    @InjectModel(Alert.name) private alertModel: Model<AlertDocument>,
  ) {}

  async createFallAlert(data: CreateAlertDto) {
    // const recentAlert = await this.alertModel.findOne({
    //   patientId: data.patientId,
    //   caregiverId: data.patientId,
    //   type:'FALL',
    //   createdAt: { $gte: new Date(Date.now() - 30_000)},
    // });

    // if (recentAlert){
    //   console.warn(`duplicate fall alert for caregiver${data.caregiverId}`)
    // }

    const severity =
      data.confidence > 0.85
        ? 'CRITICAL'
        : data.confidence > 0.6
          ? 'HIGH'
          : 'MEDIUM';

    const now = new Date();
    const windowStart = new Date(now.getTime() - 30_000);

    return this.alertModel.updateOne(
      {
        patientId: data.patientId,
        caregiverId: data.caregiverId,
        type: 'FALL',
        createdAt: { $gte: windowStart },
      },
      {
        $setOnInsert: {
          patientId: data.patientId,
          caregiverId: data.caregiverId,
          type: 'FALL',
          confidance: data.confidence,
          severity,
          acknowledged: false,
          createdAt: now,
        },
      },
      { upsert: true },
    );
  }

  async getAlertsForCaregiver(caregiverId: string) {
    return this.alertModel.find({ caregiverId }).sort({ createdAt: -1 });
  }

  async acknowledgeAlert(alertId: string) {
    return this.alertModel.findByIdAndUpdate(
      alertId,
      { acknowledged: true },
      { new: true },
    );
  }
}
