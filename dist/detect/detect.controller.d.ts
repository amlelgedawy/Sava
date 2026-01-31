import { DetectService } from './detect.service';
import type { Response } from 'express';
export declare class DetectController {
    private readonly detectService;
    constructor(detectService: DetectService);
    detect(file: Express.Multer.File, res: Response): Promise<void>;
}
