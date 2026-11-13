import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'crypto';

import { CatalogueService } from '../catalogue/catalogue.service';
import { LibraryService } from '../library/library.service';
import { PaymentsStore } from './payments.store';

@Injectable()
export class PaymentsService {
  constructor(
    @Inject(PaymentsStore) private readonly store: PaymentsStore,
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(LibraryService) private readonly library: LibraryService,
  ) {}

  createIntent(uid: string, titleId: string) {
    const title = this.catalogue.getTitle(titleId);
    if (title.priceMinor <= 0) {
      throw new BadRequestException('Free titles do not need a payment intent');
    }
    const intent = this.store.create({
      uid,
      titleId,
      amountMinor: title.priceMinor,
      currency: title.currency || 'ZMW',
    });
    return {
      id: intent.id,
      titleId: intent.titleId,
      amountMinor: intent.amountMinor,
      currency: intent.currency,
      status: intent.status,
      mode: this.mode(),
    };
  }

  /**
   * Local / sandbox confirmation — never call a real processor.
   * Requires PAYMENTS_MODE=simulate (default).
   */
  confirmSimulated(uid: string, intentId: string) {
    if (this.mode() !== 'simulate') {
      throw new ForbiddenException(
        'Simulated confirmation is disabled. Complete payment via a verified provider webhook.',
      );
    }
    const onCloud = Boolean(process.env.K_SERVICE || process.env.FORCE_CLOUD_SECURITY === 'true');
    if (onCloud && (process.env.ALLOW_SIMULATED_PAYMENTS ?? '').toLowerCase() !== 'true') {
      throw new ForbiddenException(
        'Simulated payments are disabled on Cloud Run. Set ALLOW_SIMULATED_PAYMENTS=true for prototype testing, or use webhooks.',
      );
    }
    const intent = this.store.get(intentId);
    if (!intent) throw new NotFoundException(`Payment intent ${intentId} not found`);
    if (intent.uid !== uid) throw new ForbiddenException('Payment intent belongs to another user');
    if (intent.status === 'succeeded') {
      return this.successPayload(intent.id, intent.titleId, uid);
    }
    if (intent.status !== 'requires_confirmation' && intent.status !== 'processing') {
      throw new BadRequestException(`Intent is ${intent.status}`);
    }
    this.store.mark(intentId, 'succeeded', { providerRef: `sim_${intentId}` });
    const granted = this.library.grant(uid, intent.titleId);
    return {
      ...this.successPayload(intentId, intent.titleId, uid),
      ownedIds: granted.ownedIds,
    };
  }

  /**
   * Provider webhook. Signature: hex HMAC-SHA256 of raw body with PAYMENT_WEBHOOK_SECRET.
   * Header: `x-listen-signature` or `x-webhook-signature`.
   */
  handleWebhook(rawBody: string, signatureHeader?: string, eventIdHeader?: string) {
    this.assertWebhookSignature(rawBody, signatureHeader);

    let body: {
      eventId?: string;
      type?: string;
      intentId?: string;
      uid?: string;
      titleId?: string;
      status?: string;
      providerRef?: string;
    };
    try {
      body = JSON.parse(rawBody) as typeof body;
    } catch {
      throw new BadRequestException('Webhook body must be JSON');
    }

    const eventId = eventIdHeader || body.eventId || `anon_${Date.now()}`;
    if (this.store.hasProcessedEvent(eventId)) {
      return { ok: true, duplicate: true, eventId };
    }

    if (body.type !== 'payment.succeeded' && body.status !== 'succeeded') {
      this.store.markEventProcessed(eventId);
      return { ok: true, ignored: true, eventId, type: body.type ?? body.status };
    }

    const intentId = body.intentId;
    if (!intentId) throw new BadRequestException('intentId required');
    const intent = this.store.get(intentId);
    if (!intent) throw new NotFoundException(`Payment intent ${intentId} not found`);

    if (body.uid && body.uid !== intent.uid) {
      throw new BadRequestException('Webhook uid does not match intent');
    }
    if (body.titleId && body.titleId !== intent.titleId) {
      throw new BadRequestException('Webhook titleId does not match intent');
    }

    if (intent.status !== 'succeeded') {
      this.store.mark(intentId, 'succeeded', {
        providerRef: body.providerRef || `wh_${eventId}`,
      });
      this.library.grant(intent.uid, intent.titleId);
    }
    this.store.markEventProcessed(eventId);
    return {
      ok: true,
      eventId,
      intentId,
      titleId: intent.titleId,
      uid: intent.uid,
      status: 'succeeded',
    };
  }

  private mode(): 'simulate' | 'live' {
    const raw = (process.env.PAYMENTS_MODE ?? 'simulate').toLowerCase();
    return raw === 'live' ? 'live' : 'simulate';
  }

  private successPayload(intentId: string, titleId: string, uid: string) {
    return {
      id: intentId,
      titleId,
      uid,
      status: 'succeeded' as const,
    };
  }

  private assertWebhookSignature(rawBody: string, signatureHeader?: string) {
    const secret = process.env.PAYMENT_WEBHOOK_SECRET?.trim();
    if (!secret) {
      if (this.mode() === 'simulate') return;
      throw new UnauthorizedException('PAYMENT_WEBHOOK_SECRET is required in live mode');
    }
    if (!signatureHeader) {
      throw new UnauthorizedException('Missing webhook signature');
    }
    const expected = createHmac('sha256', secret).update(rawBody).digest('hex');
    const provided = signatureHeader.replace(/^sha256=/i, '').trim();
    const a = Buffer.from(expected);
    const b = Buffer.from(provided);
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new UnauthorizedException('Invalid webhook signature');
    }
  }
}
