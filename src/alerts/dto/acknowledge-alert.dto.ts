import { IsBoolean } from "class-validator";

export class AcknowledgeAlertDto {
    @IsBoolean()
    acjnowledged: boolean;
}