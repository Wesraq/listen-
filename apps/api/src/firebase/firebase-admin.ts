import { Logger } from '@nestjs/common';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import type * as admin from 'firebase-admin';

const logger = new Logger('FirebaseAdmin');

let app: admin.app.App | null = null;
let adminModule: typeof import('firebase-admin') | null = null;

function loadServiceAccountFromDisk(): admin.ServiceAccount | null {
  const candidates = [
    process.env.FIREBASE_SERVICE_ACCOUNT_FILE?.trim(),
    join(process.cwd(), 'service-account.json'),
    join(process.cwd(), '.secrets', 'service-account.json'),
  ].filter(Boolean) as string[];

  for (const path of candidates) {
    try {
      if (!existsSync(path)) continue;
      const raw = JSON.parse(readFileSync(path, 'utf8')) as admin.ServiceAccount;
      logger.log(`Loaded Firebase service account from ${path}`);
      return raw;
    } catch (error) {
      logger.warn(`Failed reading service account at ${path}: ${error}`);
    }
  }
  return null;
}

/**
 * Shared Firebase Admin bootstrap for Auth + Firestore.
 * Prefer FIREBASE_SERVICE_ACCOUNT_JSON, FIREBASE_SERVICE_ACCOUNT_FILE,
 * apps/api/service-account.json, or GOOGLE_APPLICATION_CREDENTIALS.
 */
export async function getFirebaseAdmin(): Promise<typeof import('firebase-admin') | null> {
  if (adminModule && app) return adminModule;

  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  if (!projectId) {
    logger.warn('FIREBASE_PROJECT_ID not set — Firebase Admin unavailable.');
    return null;
  }

  try {
    const mod = await import('firebase-admin');
    if (mod.apps.length > 0) {
      adminModule = mod;
      app = mod.app();
      return mod;
    }

    // Cloud Run / GCE: prefer the runtime service account (ADC).
    const onGcp = Boolean(process.env.K_SERVICE || process.env.GOOGLE_CLOUD_PROJECT);
    const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
    const fileCred = json || onGcp ? null : loadServiceAccountFromDisk();
    if (json) {
      const cred = JSON.parse(json) as admin.ServiceAccount;
      app = mod.initializeApp({
        credential: mod.credential.cert(cred),
        projectId,
        storageBucket:
          process.env.FIREBASE_STORAGE_BUCKET?.trim() || `${projectId}.firebasestorage.app`,
      });
      logger.log('Firebase Admin initialized from FIREBASE_SERVICE_ACCOUNT_JSON.');
    } else if (fileCred) {
      app = mod.initializeApp({
        credential: mod.credential.cert(fileCred),
        projectId,
        storageBucket:
          process.env.FIREBASE_STORAGE_BUCKET?.trim() || `${projectId}.firebasestorage.app`,
      });
      logger.log('Firebase Admin initialized from service-account file.');
    } else if (onGcp || process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim()) {
      app = mod.initializeApp({
        credential: mod.credential.applicationDefault(),
        projectId,
        storageBucket:
          process.env.FIREBASE_STORAGE_BUCKET?.trim() || `${projectId}.firebasestorage.app`,
      });
      logger.log('Firebase Admin initialized from application default credentials.');
    } else {
      app = mod.initializeApp({ projectId });
      logger.warn(
        'Firebase Admin project-only init (no service account). Firestore writes will fail until credentials are set.',
      );
    }

    adminModule = mod;
    return mod;
  } catch (error) {
    logger.error(`Firebase Admin init failed: ${error}`);
    return null;
  }
}

export function firebaseProjectId(): string | undefined {
  return process.env.FIREBASE_PROJECT_ID?.trim() || undefined;
}
