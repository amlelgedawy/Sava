export interface FrameMeta {
  mime: string;
  size: number;
  name: string;
}
export interface FallPayload {
  source: 'camera' | 'accelerometer';
  bbox?: number[];
  frameMeta?: FrameMeta;
}

export interface FacePayload {
  recognized: boolean;
  faceId?: string;
  name?: string;
  frameMeta?: FrameMeta;
}

export interface ObjectPayload {
  object: string;
  bbox?: number[];
  frameMeta?: FrameMeta;
}

export type EventPayload = FallPayload | FacePayload | ObjectPayload;
