import { Injectable, UnauthorizedException } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'crypto';

@Injectable()
export class MediaSigningService {
  private secret(): string | null {
    const value = process.env.MEDIA_SIGNING_SECRET?.trim();
    return value || null;
  }

  private onCloud(): boolean {
    return Boolean(process.env.K_SERVICE || process.env.FORCE_CLOUD_SECURITY === 'true');
  }

  /** Cloud Run requires signatures; local LAN stays open unless MEDIA_REQUIRE_SIGNED=true. */
  requireSigned(): boolean {
    if ((process.env.MEDIA_REQUIRE_SIGNED ?? '').toLowerCase() === 'false') return false;
    if ((process.env.MEDIA_REQUIRE_SIGNED ?? '').toLowerCase() === 'true') return true;
    if (this.onCloud()) return true;
    return Boolean(this.secret());
  }

  sign(mediaId: string, ttlSeconds = 3600): { url: string; exp: number; sig: string } {
    const secret = this.secret() ?? (this.onCloud() ? null : 'listen-dev-media-signing');
    if (!secret) {
      throw new UnauthorizedException('MEDIA_SIGNING_SECRET is required to mint media URLs');
    }
    const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
    const sig = this.hmac(mediaId, exp, secret);
    return {
      url: `/v1/media/${encodeURIComponent(mediaId)}?exp=${exp}&sig=${sig}`,
      exp,
      sig,
    };
  }

  assertValid(mediaId: string, expRaw?: string, sig?: string) {
    if (!this.requireSigned()) return;
    const secret = this.secret();
    if (!secret) {
      throw new UnauthorizedException('Media signing is required but MEDIA_SIGNING_SECRET is unset');
    }
    const exp = Number(expRaw);
    if (!Number.isFinite(exp) || !sig) {
      throw new UnauthorizedException('Missing media signature');
    }
    if (exp < Math.floor(Date.now() / 1000)) {
      throw new UnauthorizedException('Media signature expired');
    }
    const expected = this.hmac(mediaId, exp, secret);
    const a = Buffer.from(expected);
    const b = Buffer.from(sig);
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new UnauthorizedException('Invalid media signature');
    }
  }

  private hmac(mediaId: string, exp: number, secret: string): string {
    return createHmac('sha256', secret).update(`${mediaId}.${exp}`).digest('hex');
  }
}
