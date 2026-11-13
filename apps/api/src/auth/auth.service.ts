import { Injectable, UnauthorizedException } from '@nestjs/common';

import { AuthUser } from './auth.types';

/**
 * Auth for the first API slice.
 *
 * AUTH_MODE=dev (default): `Authorization: Bearer <uid>` — suitable for simulator wiring.
 * Later: verify Firebase ID tokens with firebase-admin using FIREBASE_PROJECT_ID + service account.
 */
@Injectable()
export class AuthService {
  async resolveUser(authorizationHeader?: string): Promise<AuthUser> {
    if (!authorizationHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing Bearer token');
    }

    const token = authorizationHeader.slice('Bearer '.length).trim();
    if (!token) {
      throw new UnauthorizedException('Empty Bearer token');
    }

    const mode = (process.env.AUTH_MODE ?? 'dev').toLowerCase();
    if (mode === 'dev') {
      // Optional encoded form: uid|email|name
      const [uid, email, displayName] = token.split('|');
      if (!uid) throw new UnauthorizedException('Invalid dev token');
      return {
        uid,
        email: email || undefined,
        displayName: displayName || undefined,
      };
    }

    throw new UnauthorizedException(
      'Firebase token verification is not configured yet. Set AUTH_MODE=dev for local development.',
    );
  }
}
