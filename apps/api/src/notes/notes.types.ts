export type NoteKind = 'text' | 'voice';
export type NoteAnchor = 'chapter' | 'audio';

export interface ContentNote {
  id: string;
  uid: string;
  titleId: string;
  kind: NoteKind;
  anchor: NoteAnchor;
  locationId: string;
  /** Chapter scroll 0–1 or audio seconds. */
  position: number;
  text?: string;
  voiceDurationSec?: number;
  voiceRef?: string;
  createdAt: string;
}
