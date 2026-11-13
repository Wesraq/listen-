import { Injectable, NotFoundException } from '@nestjs/common';
import { createReadStream, existsSync, mkdirSync, writeFileSync, readFileSync } from 'fs';
import { join } from 'path';
import { randomUUID } from 'crypto';
import type { Readable } from 'stream';

export interface MediaMeta {
  id: string;
  originalName: string;
  mimeType: string;
  bytes: number;
  createdAt: string;
  creatorUid?: string;
}

@Injectable()
export class MediaStore {
  private readonly root = join(process.cwd(), '.data', 'media');
  private readonly indexPath = join(this.root, 'index.json');
  private readonly items = new Map<string, MediaMeta>();

  constructor() {
    mkdirSync(this.root, { recursive: true });
    this.load();
  }

  private load() {
    if (!existsSync(this.indexPath)) return;
    try {
      const raw = JSON.parse(readFileSync(this.indexPath, 'utf8')) as MediaMeta[];
      for (const item of raw) this.items.set(item.id, item);
    } catch {
      // ignore corrupt index in prototype
    }
  }

  private persist() {
    writeFileSync(this.indexPath, JSON.stringify([...this.items.values()], null, 2), 'utf8');
  }

  save(input: {
    buffer: Buffer;
    originalName: string;
    mimeType?: string;
    creatorUid?: string;
  }): MediaMeta {
    const id = `media-${randomUUID()}`;
    const meta: MediaMeta = {
      id,
      originalName: input.originalName || 'audio.bin',
      mimeType: input.mimeType || 'application/octet-stream',
      bytes: input.buffer.length,
      createdAt: new Date().toISOString(),
      creatorUid: input.creatorUid,
    };
    writeFileSync(join(this.root, id), input.buffer);
    this.items.set(id, meta);
    this.persist();
    return meta;
  }

  getMeta(id: string): MediaMeta {
    const meta = this.items.get(id);
    if (!meta) throw new NotFoundException(`Media ${id} not found`);
    return meta;
  }

  open(id: string): { meta: MediaMeta; stream: Readable; absolutePath: string } {
    const meta = this.getMeta(id);
    const absolutePath = join(this.root, id);
    if (!existsSync(absolutePath)) {
      throw new NotFoundException(`Media file ${id} missing on disk`);
    }
    return { meta, stream: createReadStream(absolutePath), absolutePath };
  }
}
