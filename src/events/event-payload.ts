export type EventPayload = 
|FallPayload
|FacePayload
|ObjectPayload;

export interface FallPayload{
    source: 'camera' | 'accelerometer';
    bbox?: number[];
} 

export interface FacePayload {
    recognized: boolean;
    faceId?: string;
    name?: string;
}

export interface ObjectPayload {
    object: string;
    bbox?: number[];
}