import { IsMongoId, IsOptional, IsString, IsEnum } from "class-validator";
import { FrameSource } from "../frame-source.enum";

export class IngestFrameDto {
    @IsMongoId()
    patientId: string;
    @IsOptional()
    @IsEnum(FrameSource)
    source?: FrameSource;
}