import { Controller, Get, Param, Patch } from '@nestjs/common';
import { AlertsService } from './alerts.service';

@Controller('alerts')
export class AlertsController {
    constructor( private readonly alertService: AlertsService) {}

    @Get('caregiver/:Id')
    getCaregiverAlerts(@Param('Id') caregiverId: string) {
        return this.alertService.getAlertsForCaregiver(caregiverId);
    }

    @Patch(':id/acknowledge')
    acknowledge(@Param('id') alertId: string) {
         return this.alertService.acknowledgeAlert(alertId);
    }
}
