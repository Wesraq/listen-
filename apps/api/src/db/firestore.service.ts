import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import type { Firestore } from 'firebase-admin/firestore';

import { getFirebaseAdmin } from '../firebase/firebase-admin';

/**
 * Cloud Firestore document helpers for shared prototype state.
 * Collection names are prefixed with `listen_` to keep the project tidy.
 */
@Injectable()
export class FirestoreService implements OnModuleInit {
  private readonly logger = new Logger(FirestoreService.name);
  private db: Firestore | null = null;
  private ready = false;

  get enabled() {
    return this.ready && this.db != null;
  }

  async onModuleInit() {
    const backend = (process.env.DATA_BACKEND ?? 'postgres').toLowerCase();
    if (backend !== 'firestore') {
      this.logger.log(`DATA_BACKEND=${backend} — Firestore persistence idle.`);
      return;
    }

    const admin = await getFirebaseAdmin();
    if (!admin) {
      this.logger.error('Firestore requested but Firebase Admin is unavailable.');
      return;
    }

    try {
      this.db = admin.firestore();
      // Smoke read — fails fast without a service account / ADC.
      await this.db.collection(this.col('_health')).limit(1).get();
      this.ready = true;
      this.logger.log('Cloud Firestore connected (DATA_BACKEND=firestore).');
    } catch (error) {
      this.ready = false;
      this.db = null;
      this.logger.error(
        `Firestore unavailable — set FIREBASE_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS. ${error}`,
      );
    }
  }

  /** Namespaced collection. */
  col(name: string): string {
    const prefix = (process.env.FIRESTORE_PREFIX ?? 'listen').replace(/_+$/, '');
    return `${prefix}_${name}`;
  }

  async list<T extends Record<string, unknown>>(
    collection: string,
  ): Promise<Array<T & { id: string }>> {
    this.assertReady();
    const snap = await this.db!.collection(this.col(collection)).get();
    return snap.docs.map((doc) => {
      const data = doc.data() as T;
      return { ...data, id: doc.id };
    });
  }

  async get<T extends Record<string, unknown>>(
    collection: string,
    id: string,
  ): Promise<(T & { id: string }) | null> {
    this.assertReady();
    const snap = await this.db!.collection(this.col(collection)).doc(id).get();
    if (!snap.exists) return null;
    return { ...(snap.data() as T), id: snap.id };
  }

  async set(collection: string, id: string, data: Record<string, unknown>): Promise<void> {
    this.assertReady();
    const { id: _omit, ...rest } = data;
    await this.db!.collection(this.col(collection)).doc(id).set(
      {
        ...rest,
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    );
  }

  async delete(collection: string, id: string): Promise<void> {
    this.assertReady();
    await this.db!.collection(this.col(collection)).doc(id).delete();
  }

  async clearCollection(collection: string): Promise<void> {
    this.assertReady();
    const snap = await this.db!.collection(this.col(collection)).get();
    const batchSize = 400;
    let batch = this.db!.batch();
    let count = 0;
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
      count += 1;
      if (count >= batchSize) {
        await batch.commit();
        batch = this.db!.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
  }

  private assertReady() {
    if (!this.db || !this.ready) {
      throw new Error('Cloud Firestore is not available');
    }
  }
}
