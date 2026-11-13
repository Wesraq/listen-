import { Injectable, Logger, OnModuleInit, UnauthorizedException } from '@nestjs/common';
import { createHash } from 'crypto';

import { getFirebaseAdmin } from '../firebase/firebase-admin';
import { AuthUser } from './auth.types';

type AuthMode = 'dev' | 'firebase' | 'hybrid';

/**
 * Auth for the Listen+ API.
 *
 * AUTH_MODE:
 * - `dev` — `Authorization: Bearer <uid>` or `uid|email|name` (local only)
 * - `firebase` — Firebase ID tokens only
 * - `hybrid` — Firebase JWTs, else dev tokens (LAN only — forced off on Cloud Run)
 *
 * On Cloud Run (`K_SERVICE` set), AUTH_MODE defaults to `firebase` and
 * hybrid/dev are ignored unless ALLOW_INSECURE_AUTH=true.
 */
@Injectable()
export class AuthService implements OnModuleInit {
  private readonly logger = new Logger(AuthService.name);
  private firebaseReady = false;
  private adminApp: typeof import('firebase-admin') | null = null;

  async onModuleInit() {
    this.adminApp = await getFirebaseAdmin();
    this.firebaseReady = this.adminApp != null;
    const mode = this.mode();
    this.logger.log(
      `AuthService ready mode=${mode} firebaseReady=${this.firebaseReady} cloud=${this.onCloud()}`,
    );
    if (mode === 'firebase' && !this.firebaseReady && !process.env.FIREBASE_WEB_API_KEY?.trim()) {
      this.logger.error(
        'AUTH_MODE=firebase but Firebase Admin / WEB_API_KEY are unavailable — authenticated calls will fail.',
      );
    }
  }

  private onCloud(): boolean {
    return Boolean(process.env.K_SERVICE || process.env.FORCE_CLOUD_SECURITY === 'true');
  }

  private mode(): AuthMode {
    const onCloud = this.onCloud();
    const raw = (process.env.AUTH_MODE ?? (onCloud ? 'firebase' : 'hybrid')).toLowerCase();
    const requested: AuthMode =
      raw === 'dev' || raw === 'firebase' || raw === 'hybrid' ? raw : onCloud ? 'firebase' : 'hybrid';

    if (onCloud && (requested === 'hybrid' || requested === 'dev')) {
      const allowInsecure = (process.env.ALLOW_INSECURE_AUTH ?? '').toLowerCase() === 'true';
      if (!allowInsecure) {
        this.logger.warn(
          `AUTH_MODE=${requested} blocked on Cloud Run — using firebase. Set ALLOW_INSECURE_AUTH=true to override.`,
        );
        return 'firebase';
      }
    }
    return requested;
  }

  /** True when the resolved identity came from a verified Firebase ID token. */
  isFirebaseMode(): boolean {
    return this.mode() === 'firebase';
  }

  async resolveUser(authorizationHeader?: string): Promise<AuthUser> {
    if (!authorizationHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing Bearer token');
    }

    const token = authorizationHeader.slice('Bearer '.length).trim();
    if (!token) {
      throw new UnauthorizedException('Empty Bearer token');
    }

    const mode = this.mode();
    const looksLikeJwt = token.split('.').length === 3;

    if (mode === 'firebase' || (mode === 'hybrid' && looksLikeJwt)) {
      const user = await this.verifyFirebaseToken(token);
      if (user) return user;
      if (mode === 'firebase') {
        throw new UnauthorizedException('Invalid Firebase ID token');
      }
    }

    if (mode === 'dev' || mode === 'hybrid') {
      return this.resolveDevToken(token);
    }

    throw new UnauthorizedException('Firebase token verification failed.');
  }

  private resolveDevToken(token: string): AuthUser {
    const [uid, email, displayName] = token.split('|');
    if (!uid) throw new UnauthorizedException('Invalid dev token');
    if (uid.split('.').length === 3) {
      throw new UnauthorizedException('Invalid Bearer token');
    }
    // Never trust email from a spoofable local token for rebind — omit email.
    return {
      uid,
      email: undefined,
      displayName: displayName || undefined,
    };
  }

  private async verifyFirebaseToken(token: string): Promise<AuthUser | null> {
    if (this.firebaseReady && this.adminApp) {
      try {
        const decoded = await this.adminApp.auth().verifyIdToken(token);
        return {
          uid: decoded.uid,
          email: decoded.email,
          displayName: typeof decoded.name === 'string' ? decoded.name : undefined,
        };
      } catch (error) {
        this.logger.debug(`verifyIdToken failed: ${error}`);
      }
    }

    return this.verifyViaIdentityToolkit(token);
  }

  private async verifyViaIdentityToolkit(token: string): Promise<AuthUser | null> {
    const apiKey = process.env.FIREBASE_WEB_API_KEY?.trim();
    if (!apiKey) return null;

    try {
      const response = await fetch(
        `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${apiKey}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ idToken: token }),
        },
      );
      if (!response.ok) {
        this.logger.debug(`Identity Toolkit lookup HTTP ${response.status}`);
        return null;
      }
      const body = (await response.json()) as {
        users?: Array<{ localId?: string; email?: string; displayName?: string }>;
      };
      const user = body.users?.[0];
      if (!user?.localId) return null;
      return {
        uid: user.localId,
        email: user.email,
        displayName: user.displayName,
      };
    } catch (error) {
      this.logger.debug(`Identity Toolkit lookup error: ${error}`);
      return null;
    }
  }

  tokenFingerprint(token: string): string {
    return createHash('sha256').update(token).digest('hex').slice(0, 12);
  }
}
