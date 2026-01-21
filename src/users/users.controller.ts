import { Controller, Post, Body, Get, Param } from '@nestjs/common';
import { UserService } from './users.service';
import { CreateCaregiverDto } from './dto/create-caregiver.dto';
import { CreatePatientDto } from './dto/create-patient.dto';
import { AssignPatientDto } from './dto/assign-patient.dto';

@Controller('/users')
export class UserController {
  constructor(private readonly UserService: UserService) {}

  @Post('caregiver')
  createCaregiver(@Body() dto: CreateCaregiverDto) {
    return this.UserService.CreateCaregiver(dto.name, dto.email);
  }
  @Post('patient')
  createPatient(@Body() dto: CreatePatientDto) {
    return this.UserService.createPatient(dto.name);
  }
  @Post('assign')
  assignPatient(@Body() dto: AssignPatientDto) {
    return this.UserService.assignPatientToCaregiver(
      dto.caregiverId,
      dto.patientId,
    );
  }
  @Get('caregiver/:id/patients')
  getPatient(@Param('id')id:string){
    return this.UserService.getCargiverPatients(id);
  }
}
