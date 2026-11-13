import { Inject, Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import { createReadStream, existsSync, mkdirSync, writeFileSync, readFileSync } from 'fs';
import { join } from 'path';
import { randomUUID } from 'crypto';
import { Readable } from 'stream';

import { getFirebaseAdmin } from '../firebase/firebase-admin';
import { FirestoreService } from '../db/firestore.service';

export interface MediaMeta {
  id: string;
  originalName: string;
  mimeType: string;
  bytes: number;
  createdAt: string;
  creatorUid?: string;
  /** Firebase Storage object path when stored in the cloud. */
  storagePath?: string;
}

/**
 * Media bytes live in Firebase Storage when DATA_BACKEND=firestore (or
 * MEDIA_BACKEND=firebase). Metadata is kept in Firestore `listen_media`.
 * Falls back to local `.data/media` for pure LAN/disk mode.
 */
@Injectable()
export class MediaStore implements OnModuleInit {
  private readonly logger = new Logger(MediaStore.name);
  private readonly root = join(process.cwd(), '.data', 'media');
  private readonly indexPath = join(this.root, 'index.json');
  private readonly items = new Map<string, MediaMeta>();
  private storageBucket: string | null = null;
  private useCloud = false;

  constructor(@Inject(FirestoreService) private readonly fs: FirestoreService) {
    mkdirSync(this.root, { recursive: true });
    this.load();
  }

  async onModuleInit() {
    const backend = (process.env.MEDIA_BACKEND ?? process.env.DATA_BACKEND ?? 'disk').toLowerCase();
    this.useCloud = backend === 'firestore' || backend === 'firebase';
    this.storageBucket =
      process.env.FIREBASE_STORAGE_BUCKET?.trim() ||
      (process.env.FIREBASE_PROJECT_ID
        ? `${process.env.FIREBASE_PROJECT_ID}.firebasestorage.app`
        : null);

    if (this.useCloud && this.fs.enabled) {
      await this.loadFromFirestore();
      this.logger.log(
        `Media store using Firebase Storage bucket=${this.storageBucket} (${this.items.size} object(s))`,
      );
    } else if (this.useCloud) {
      this.logger.warn(
        'MEDIA cloud mode requested but Firestore is offline — media will use local disk fallback.',
      );
      this.useCloud = false;
    }
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

  private persistDiskIndex() {
    writeFileSync(this.indexPath, JSON.stringify([...this.items.values()], null, 2), 'utf8');
  }

  private async loadFromFirestore() {
    try {
      const rows = await this.fs.list<{ payload?: MediaMeta } & Partial<MediaMeta>>('media');
      for (const row of rows) {
        const meta = (row.payload ?? row) as MediaMeta;
        if (meta?.id) this.items.set(meta.id, meta);
      }
    } catch (error) {
      this.logger.warn(`Failed to load media index from Firestore: ${error}`);
    }
  }

  private async persistMeta(meta: MediaMeta) {
    this.items.set(meta.id, meta);
    if (this.useCloud && this.fs.enabled) {
      try {
        await this.fs.set('media', meta.id, { payload: meta, ...meta });
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist media meta to Firestore: ${error}`);
      }
    }
    this.persistDiskIndex();
  }

  async save(input: {
    buffer: Buffer;
    originalName: string;
    mimeType?: string;
    creatorUid?: string;
  }): Promise<MediaMeta> {
    const id = `media-${randomUUID()}`;
    const meta: MediaMeta = {
      id,
      originalName: input.originalName || 'audio.bin',
      mimeType: input.mimeType || 'application/octet-stream',
      bytes: input.buffer.length,
      createdAt: new Date().toISOString(),
      creatorUid: input.creatorUid,
    };

    if (this.useCloud && this.storageBucket) {
      const admin = await getFirebaseAdmin();
      if (!admin) throw new Error('Firebase Admin unavailable for media upload');
      const path = `media/${id}/${meta.originalName.replace(/[^\w.\-]+/g, '_')}`;
      const bucket = admin.storage().bucket(this.storageBucket);
      const file = bucket.file(path);
      await file.save(input.buffer, {
        contentType: meta.mimeType,
        resumable: false,
        metadata: {
          metadata: {
            creatorUid: input.creatorUid || '',
            originalName: meta.originalName,
          },
        },
      });
      meta.storagePath = path;
      await this.persistMeta(meta);
      return meta;
    }

    writeFileSync(join(this.root, id), input.buffer);
    await this.persistMeta(meta);
    return meta;
  }

  getMeta(id: string): MediaMeta {
    const meta = this.items.get(id);
    if (!meta) throw new NotFoundException(`Media ${id} not found`);
    return meta;
  }

  /** Resolve meta from memory, Firestore, or by probing Storage under media/{id}/. */
  async ensureMeta(id: string): Promise<MediaMeta> {
    const cached = this.items.get(id);
    if (cached) return cached;

    if (this.useCloud && this.fs.enabled) {
      try {
        const row = await this.fs.get<{ payload?: MediaMeta } & Partial<MediaMeta>>('media', id);
        if (row) {
          const meta = ((row.payload ?? row) as MediaMeta);
          if (meta?.id) {
            this.items.set(meta.id, meta);
            return meta;
          }
        }
      } catch (error) {
        this.logger.warn(`Firestore media lookup failed for ${id}: ${error}`);
      }
    }

    if (this.useCloud && this.storageBucket) {
      try {
        const admin = await getFirebaseAdmin();
        if (admin) {
          const bucket = admin.storage().bucket(this.storageBucket);
          const [files] = await bucket.getFiles({ prefix: `media/${id}/`, maxResults: 5 });
          if (files.length > 0) {
            const file = files[0];
            const [metadata] = await file.getMetadata();
            const meta: MediaMeta = {
              id,
              originalName: file.name.split('/').pop() || `${id}.bin`,
              mimeType: (metadata.contentType as string) || 'application/octet-stream',
              bytes: Number(metadata.size ?? 0) || 0,
              createdAt: (metadata.timeCreated as string) || new Date().toISOString(),
              storagePath: file.name,
              creatorUid: (metadata.metadata?.creatorUid as string) || undefined,
            };
            await this.persistMeta(meta);
            this.logger.log(`Recovered media meta for ${id} from Storage path ${file.name}`);
            return meta;
          }
        }
      } catch (error) {
        this.logger.warn(`Storage probe failed for ${id}: ${error}`);
      }
    }

    throw new NotFoundException(`Media ${id} not found`);
  }

  async open(
    id: string,
  ): Promise<{ meta: MediaMeta; stream: Readable; absolutePath?: string }> {
    const meta = await this.ensureMeta(id);

    if (meta.storagePath && this.storageBucket) {
      const admin = await getFirebaseAdmin();
      if (!admin) throw new NotFoundException(`Media ${id} unavailable (no Firebase Admin)`);
      const file = admin.storage().bucket(this.storageBucket).file(meta.storagePath);
      const [exists] = await file.exists();
      if (!exists) throw new NotFoundException(`Media file ${id} missing in Storage`);
      return { meta, stream: file.createReadStream() };
    }

    const absolutePath = join(this.root, id);
    if (!existsSync(absolutePath)) {
      throw new NotFoundException(`Media file ${id} missing on disk`);
    }
    return { meta, stream: createReadStream(absolutePath), absolutePath };
  }
}
