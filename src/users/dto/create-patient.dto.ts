import { IsNotEmpty, IsString } from 'class-validator';

export class CreatePatientDto{
    @IsNotEmpty()
    @IsString()
    name : string;
}