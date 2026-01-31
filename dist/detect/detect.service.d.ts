export declare class DetectService {
    private readonly fastApiUrl;
    detectDangerousObjects(file: Express.Multer.File): Promise<Buffer>;
}
