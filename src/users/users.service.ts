import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { User, UserRole } from './user.schema';

@Injectable()
export class UserService {
  constructor(
    @InjectModel(User.name)
    private UserModel: Model<User>,
  ) {}
  async CreateCaregiver(name: string, email: string) {
    return this.UserModel.create({
      name,
      email,
      role: UserRole.CAREGIVER,
    });
  }
  async createPatient(name: string) {
    return this.UserModel.create({
      name,
      role: UserRole.PATIENT,
    });
  }

  async assignPatientToCaregiver(cargiverId: string, patientId: string) {
    const caregiver = await this.UserModel.findById(cargiverId);
    const patient = await this.UserModel.findById(patientId);

    if (!caregiver || caregiver.role !== UserRole.CAREGIVER) {
      throw new NotFoundException('caregiver not found');
    }
    if (!patient || patient.role !== UserRole.PATIENT) {
      throw new NotFoundException('patient not found ');
    }

    caregiver.assignedPatients = [
      ...(caregiver.assignedPatients || []),
      patient._id,
    ];
    patient.assignedCaregivers = [
      ...(patient.assignedCaregivers || []),
      caregiver._id,
    ];

    await caregiver.save();
    await patient.save();
    return { message: 'patient saved successfully ' };
  }
  async getCargiverPatients(caregiverId: string) {
    return this.UserModel.findById(caregiverId).populate('assignedPatients');
  }

   findById(id:string){
      return this.UserModel.findById(id);
    }
}
