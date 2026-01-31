import type { EventType } from 'src/events/fall-event.schema';

export type AiEventType = EventType;

export interface AiEventResult {
  type: AiEventType;
  confidence?: number;
  payload?: Record<string, any>;
}

export interface AiResponse {
  events: AiEventResult[];
}
