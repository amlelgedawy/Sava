import { IsEmail, IsNotEmpty, IsString } from 'class-validator';

export class CreateCaregiverDto{
    @IsString()
    @IsNotEmpty()
    name : string;

    @IsEmail()
    email: string;
}