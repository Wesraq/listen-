import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { DbService } from '../db/db.service';
import { ContentNote, NoteAnchor, NoteKind } from './notes.types';

@Injectable()
export class NotesStore implements OnModuleInit {
  private readonly logger = new Logger(NotesStore.name);
  private readonly dataFile = join(process.cwd(), '.data', 'notes.json');
  private notes: ContentNote[] = [];

  constructor(@Inject(DbService) private readonly db: DbService) {}

  async onModuleInit() {
    if (this.db.enabled) {
      await this.loadFromDb();
      if (this.notes.length === 0) {
        this.loadFromDisk();
        if (this.notes.length > 0) {
          await this.persistAllToDb();
          this.logger.log(`Migrated ${this.notes.length} note(s) from disk → Postgres`);
        }
      }
      return;
    }
    this.loadFromDisk();
  }

  private loadFromDisk() {
    try {
      if (!existsSync(this.dataFile)) return;
      const raw = JSON.parse(readFileSync(this.dataFile, 'utf8')) as { notes?: ContentNote[] };
      if (Array.isArray(raw.notes)) {
        this.notes = raw.notes;
        this.logger.log(`Loaded ${this.notes.length} note(s) from disk`);
      }
    } catch (error) {
      this.logger.warn(`Failed to load notes: ${error}`);
    }
  }

  private async loadFromDb() {
    try {
      const result = await this.db.query<{
        id: string;
        uid: string;
        title_id: string;
        kind: NoteKind;
        anchor: NoteAnchor;
        location_id: string;
        position: number;
        body_text: string | null;
        voice_duration_sec: number | null;
        voice_ref: string | null;
        created_at: Date;
      }>(
        `SELECT id, uid, title_id, kind, anchor, location_id, position,
                body_text, voice_duration_sec, voice_ref, created_at
         FROM notes
         ORDER BY created_at DESC`,
      );
      this.notes = result.rows.map((row) => ({
        id: row.id,
        uid: row.uid,
        titleId: row.title_id,
        kind: row.kind,
        anchor: row.anchor,
        locationId: row.location_id,
        position: Number(row.position) || 0,
        text: row.body_text ?? undefined,
        voiceDurationSec: row.voice_duration_sec ?? undefined,
        voiceRef: row.voice_ref ?? undefined,
        createdAt: new Date(row.created_at).toISOString(),
      }));
      this.logger.log(`Loaded ${this.notes.length} note(s) from Postgres`);
    } catch (error) {
      this.logger.warn(`Failed to load notes from Postgres: ${error}`);
    }
  }

  private persistDisk() {
    try {
      mkdirSync(dirname(this.dataFile), { recursive: true });
      writeFileSync(this.dataFile, JSON.stringify({ notes: this.notes }, null, 2), 'utf8');
    } catch (error) {
      this.logger.warn(`Failed to persist notes: ${error}`);
    }
  }

  private async upsertNote(note: ContentNote) {
    await this.db.query(
      `INSERT INTO notes (
         id, uid, title_id, kind, anchor, location_id, position,
         body_text, voice_duration_sec, voice_ref, created_at
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       ON CONFLICT (id) DO UPDATE SET
         uid = EXCLUDED.uid,
         title_id = EXCLUDED.title_id,
         kind = EXCLUDED.kind,
         anchor = EXCLUDED.anchor,
         location_id = EXCLUDED.location_id,
         position = EXCLUDED.position,
         body_text = EXCLUDED.body_text,
         voice_duration_sec = EXCLUDED.voice_duration_sec,
         voice_ref = EXCLUDED.voice_ref`,
      [
        note.id,
        note.uid,
        note.titleId,
        note.kind,
        note.anchor,
        note.locationId,
        note.position,
        note.text ?? null,
        note.voiceDurationSec ?? null,
        note.voiceRef ?? null,
        note.createdAt,
      ],
    );
  }

  private async persistAllToDb() {
    for (const note of this.notes) {
      await this.upsertNote(note);
    }
  }

  private persistNote(note: ContentNote) {
    if (this.db.enabled) {
      void this.upsertNote(note).catch((error) =>
        this.logger.warn(`Failed to persist note to Postgres: ${error}`),
      );
      return;
    }
    this.persistDisk();
  }

  private persistDelete(id: string) {
    if (this.db.enabled) {
      void this.db
        .query('DELETE FROM notes WHERE id = $1', [id])
        .catch((error) => this.logger.warn(`Failed to delete note in Postgres: ${error}`));
      return;
    }
    this.persistDisk();
  }

  list(uid: string, titleId?: string) {
    return this.notes.filter(
      (n) => n.uid === uid && (titleId == null || n.titleId === titleId),
    );
  }

  create(input: {
    uid: string;
    titleId: string;
    kind: NoteKind;
    anchor: NoteAnchor;
    locationId: string;
    position: number;
    text?: string;
    voiceDurationSec?: number;
    voiceRef?: string;
  }): ContentNote {
    if (input.kind === 'voice') {
      const duration = input.voiceDurationSec ?? 0;
      if (duration <= 0 || duration > 60) {
        throw new Error('Voice notes must be between 1 and 60 seconds');
      }
    }
    const note: ContentNote = {
      id: `note-${randomUUID()}`,
      uid: input.uid,
      titleId: input.titleId,
      kind: input.kind,
      anchor: input.anchor,
      locationId: input.locationId,
      position: input.position,
      text: input.text?.trim() || undefined,
      voiceDurationSec: input.voiceDurationSec,
      voiceRef: input.voiceRef,
      createdAt: new Date().toISOString(),
    };
    this.notes.unshift(note);
    this.persistNote(note);
    return note;
  }

  remove(uid: string, id: string) {
    const index = this.notes.findIndex((n) => n.id === id && n.uid === uid);
    if (index < 0) return false;
    this.notes.splice(index, 1);
    this.persistDelete(id);
    return true;
  }
}
