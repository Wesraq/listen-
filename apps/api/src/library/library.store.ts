import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { DbService } from '../db/db.service';
import { FirestoreService } from '../db/firestore.service';

interface LibraryRecord {
  owned: Set<string>;
  saved: Set<string>;
}

interface LibraryFileShape {
  users?: Record<string, { owned?: string[]; saved?: string[] }>;
}

@Injectable()
export class LibraryStore implements OnModuleInit {
  private readonly logger = new Logger(LibraryStore.name);
  private readonly dataFile = join(process.cwd(), '.data', 'library.json');
  private readonly byUser = new Map<string, LibraryRecord>();

  constructor(
    @Inject(DbService) private readonly db: DbService,
    @Inject(FirestoreService) private readonly fs: FirestoreService,
  ) {}

  async onModuleInit() {
    if (this.fs.enabled) {
      await this.loadFromFirestore();
      if (this.byUser.size === 0) {
        this.loadFromDisk();
        if (this.byUser.size > 0) {
          await this.persistAllToFirestore();
          this.logger.log(`Migrated ${this.byUser.size} library user(s) disk → Firestore`);
        }
      }
      return;
    }
    if (this.db.enabled) {
      await this.loadFromDb();
      if (this.byUser.size === 0) {
        this.loadFromDisk();
        if (this.byUser.size > 0) {
          await this.persistAllToDb();
          this.logger.log(`Migrated ${this.byUser.size} library user(s) from disk → Postgres`);
        }
      }
      return;
    }
    this.loadFromDisk();
  }

  private loadFromDisk() {
    try {
      if (!existsSync(this.dataFile)) return;
      const raw = JSON.parse(readFileSync(this.dataFile, 'utf8')) as LibraryFileShape;
      const users = raw.users ?? {};
      for (const [uid, entry] of Object.entries(users)) {
        this.byUser.set(uid, {
          owned: new Set(entry.owned ?? []),
          saved: new Set(entry.saved ?? []),
        });
      }
      this.logger.log(`Loaded library entitlements for ${this.byUser.size} user(s) from disk`);
    } catch (error) {
      this.logger.warn(`Failed to load library store: ${error}`);
    }
  }

  private async loadFromFirestore() {
    try {
      const rows = await this.fs.list<{ owned?: string[]; saved?: string[] }>('library_users');
      for (const row of rows) {
        this.byUser.set(row.id, {
          owned: new Set(row.owned ?? []),
          saved: new Set(row.saved ?? []),
        });
      }
      this.logger.log(`Loaded library entitlements for ${this.byUser.size} user(s) from Firestore`);
    } catch (error) {
      this.logger.warn(`Failed to load library from Firestore: ${error}`);
    }
  }

  private async loadFromDb() {
    try {
      const result = await this.db.query<{
        uid: string;
        title_id: string;
        kind: 'owned' | 'saved';
      }>('SELECT uid, title_id, kind FROM library_entries');
      for (const row of result.rows) {
        const entry = this.record(row.uid);
        if (row.kind === 'owned') entry.owned.add(row.title_id);
        else entry.saved.add(row.title_id);
      }
      this.logger.log(`Loaded library entitlements for ${this.byUser.size} user(s) from Postgres`);
    } catch (error) {
      this.logger.warn(`Failed to load library from Postgres: ${error}`);
    }
  }

  private persistDisk() {
    try {
      mkdirSync(dirname(this.dataFile), { recursive: true });
      const users: Record<string, { owned: string[]; saved: string[] }> = {};
      for (const [uid, entry] of this.byUser.entries()) {
        users[uid] = {
          owned: [...entry.owned],
          saved: [...entry.saved],
        };
      }
      writeFileSync(this.dataFile, JSON.stringify({ users }, null, 2), 'utf8');
    } catch (error) {
      this.logger.warn(`Failed to persist library store: ${error}`);
    }
  }

  private async persistUserToFirestore(uid: string) {
    const entry = this.record(uid);
    await this.fs.set('library_users', uid, {
      owned: [...entry.owned],
      saved: [...entry.saved],
    });
  }

  private async persistAllToFirestore() {
    for (const uid of this.byUser.keys()) {
      await this.persistUserToFirestore(uid);
    }
  }

  private async persistAllToDb() {
    await this.db.query('DELETE FROM library_entries');
    for (const [uid, entry] of this.byUser.entries()) {
      for (const titleId of entry.owned) {
        await this.db.query(
          `INSERT INTO library_entries (uid, title_id, kind) VALUES ($1, $2, 'owned')
           ON CONFLICT DO NOTHING`,
          [uid, titleId],
        );
      }
      for (const titleId of entry.saved) {
        await this.db.query(
          `INSERT INTO library_entries (uid, title_id, kind) VALUES ($1, $2, 'saved')
           ON CONFLICT DO NOTHING`,
          [uid, titleId],
        );
      }
    }
  }

  private persist(uid?: string) {
    if (this.fs.enabled) {
      if (uid) {
        void this.persistUserToFirestore(uid).catch((error) =>
          this.logger.warn(`Failed to persist library user to Firestore: ${error}`),
        );
      } else {
        void this.persistAllToFirestore().catch((error) =>
          this.logger.warn(`Failed to persist library to Firestore: ${error}`),
        );
      }
      return;
    }
    if (this.db.enabled) {
      void this.persistAllToDb().catch((error) =>
        this.logger.warn(`Failed to persist library to Postgres: ${error}`),
      );
      return;
    }
    this.persistDisk();
  }

  private record(uid: string): LibraryRecord {
    let entry = this.byUser.get(uid);
    if (!entry) {
      entry = {
        owned: new Set(),
        saved: new Set(),
      };
      this.byUser.set(uid, entry);
    }
    return entry;
  }

  getOwned(uid: string): string[] {
    return [...this.record(uid).owned];
  }

  getSaved(uid: string): string[] {
    return [...this.record(uid).saved];
  }

  isEntitled(uid: string, titleId: string, isFree: boolean): boolean {
    if (isFree) return true;
    return this.record(uid).owned.has(titleId);
  }

  grantOwnership(uid: string, titleId: string): string[] {
    this.record(uid).owned.add(titleId);
    this.persist(uid);
    return this.getOwned(uid);
  }

  rebindUid(fromUid: string, toUid: string): void {
    if (!fromUid || !toUid || fromUid === toUid) return;
    const from = this.byUser.get(fromUid);
    if (!from) return;
    const to = this.record(toUid);
    for (const id of from.owned) to.owned.add(id);
    for (const id of from.saved) to.saved.add(id);
    this.byUser.delete(fromUid);
    if (this.fs.enabled) {
      void this.fs.delete('library_users', fromUid).catch(() => undefined);
      void this.persistUserToFirestore(toUid).catch((error) =>
        this.logger.warn(`Failed to persist rebound library user: ${error}`),
      );
      return;
    }
    this.persist();
  }

  toggleSaved(uid: string, titleId: string): { saved: string[]; isSaved: boolean } {
    const entry = this.record(uid);
    if (entry.saved.has(titleId)) {
      entry.saved.delete(titleId);
      this.persist(uid);
      return { saved: [...entry.saved], isSaved: false };
    }
    entry.saved.add(titleId);
    this.persist(uid);
    return { saved: [...entry.saved], isSaved: true };
  }
}
