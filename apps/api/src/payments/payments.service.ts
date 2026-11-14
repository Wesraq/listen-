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
import { LedgerService } from '../finance/ledger.service';
import type { PaymentKind, PaymentProvider } from '../finance/finance.types';
import { LibraryService } from '../library/library.service';
import { StudioStore } from '../studio/studio.store';
import type { ContentFormat } from '../catalogue/catalogue.types';
import { PaymentsStore, type PaymentIntent } from './payments.store';

@Injectable()
export class PaymentsService {
  constructor(
    @Inject(PaymentsStore) private readonly store: PaymentsStore,
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(LibraryService) private readonly library: LibraryService,
    @Inject(LedgerService) private readonly ledger: LedgerService,
    @Inject(StudioStore) private readonly studio: StudioStore,
  ) {}

  createIntent(
    uid: string,
    input: {
      kind?: PaymentKind;
      titleId?: string;
      planId?: string;
      provider?: PaymentProvider;
      payerPhone?: string;
    },
  ) {
    const kind: PaymentKind = input.kind ?? (input.planId ? 'subscription' : 'title_purchase');
    const provider = this.normalizeProvider(input.provider);

    if (kind === 'title_purchase') {
      const titleId = input.titleId?.trim();
      if (!titleId) throw new BadRequestException('titleId is required for title purchases');
      const title = this.catalogue.getTitle(titleId);
      if (title.priceMinor <= 0 || title.monetisationMode === 'free_with_ads') {
        throw new BadRequestException('Free titles do not need a payment intent');
      }
      const intent = this.store.create({
        uid,
        kind,
        titleId,
        amountMinor: title.priceMinor,
        currency: title.currency || 'ZMW',
        provider,
        payerPhone: input.payerPhone?.trim() || undefined,
        ...this.initialProviderState(provider, input.payerPhone),
      });
      return this.publicIntent(intent);
    }

    const planId = input.planId?.trim();
    if (!planId) throw new BadRequestException('planId is required for subscriptions');
    const plan = this.ledger.getPlan(planId);
    if (!plan) throw new BadRequestException(`Unknown plan ${planId}`);
    const intent = this.store.create({
      uid,
      kind: 'subscription',
      planId: plan.id,
      amountMinor: plan.amountMinor,
      currency: plan.currency,
      provider,
      payerPhone: input.payerPhone?.trim() || undefined,
      ...this.initialProviderState(provider, input.payerPhone),
    });
    return this.publicIntent(intent);
  }

  /**
   * Local / sandbox confirmation — never calls a real processor.
   * Still posts through the shared financial ledger + grants access.
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
      return this.successPayload(intent);
    }
    if (
      intent.status !== 'requires_confirmation' &&
      intent.status !== 'requires_action' &&
      intent.status !== 'processing'
    ) {
      throw new BadRequestException(`Intent is ${intent.status}`);
    }
    this.store.mark(intentId, 'succeeded', {
      providerRef: intent.providerRef || `sim_${intentId}`,
    });
    return this.finalizeSucceeded(intentId);
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
      planId?: string;
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

    if (body.type === 'payment.failed' || body.status === 'failed') {
      if (body.intentId) {
        this.store.mark(body.intentId, 'failed', {
          providerRef: body.providerRef,
          failureReason: 'Provider reported failure',
        });
      }
      this.store.markEventProcessed(eventId);
      return { ok: true, eventId, status: 'failed' };
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
    if (body.titleId && intent.titleId && body.titleId !== intent.titleId) {
      throw new BadRequestException('Webhook titleId does not match intent');
    }
    if (body.planId && intent.planId && body.planId !== intent.planId) {
      throw new BadRequestException('Webhook planId does not match intent');
    }

    if (intent.status !== 'succeeded') {
      this.store.mark(intentId, 'succeeded', {
        providerRef: body.providerRef || `wh_${eventId}`,
      });
      this.finalizeSucceeded(intentId);
    }
    this.store.markEventProcessed(eventId);
    return {
      ok: true,
      eventId,
      intentId,
      titleId: intent.titleId,
      planId: intent.planId,
      uid: intent.uid,
      status: 'succeeded',
    };
  }

  private finalizeSucceeded(intentId: string) {
    const intent = this.store.get(intentId);
    if (!intent) throw new NotFoundException(`Payment intent ${intentId} not found`);

    if (intent.kind === 'subscription') {
      if (!intent.planId) throw new BadRequestException('Subscription intent missing planId');
      const settled = this.ledger.settleSubscription({
        intentId: intent.id,
        customerUid: intent.uid,
        planId: intent.planId,
        currency: intent.currency,
        grossMinor: intent.amountMinor,
        provider: intent.provider,
        providerRef: intent.providerRef,
      });
      return {
        ...this.successPayload(intent),
        subscription: settled.subscription,
        journalId: settled.journal.id,
        allocation: {
          feeMinor: settled.feeMinor,
          netMinor: settled.netMinor,
          creatorPoolMinor: settled.creatorPoolMinor,
          platformShareMinor: settled.platformShareMinor,
        },
      };
    }

    if (!intent.titleId) throw new BadRequestException('Purchase intent missing titleId');
    const title = this.catalogue.getTitle(intent.titleId);
    const draft = this.studio.findByPublishedTitleId(intent.titleId);
    const creatorUid = draft?.creatorUid ?? title.creatorUid;

    const settled = this.ledger.settleTitlePurchase({
      intentId: intent.id,
      customerUid: intent.uid,
      creatorUid,
      titleId: intent.titleId,
      currency: intent.currency,
      grossMinor: intent.amountMinor,
      provider: intent.provider,
      providerRef: intent.providerRef,
    });

    // Mirror creator share into Studio earnings dashboard once (cashout will read ledger).
    if (settled.created && creatorUid && settled.creatorShareMinor > 0) {
      this.studio.recordEarning({
        creatorUid,
        titleId: intent.titleId,
        titleName: title.name,
        currency: intent.currency,
        grossMinor: intent.amountMinor,
        deductionsMinor: settled.feeMinor,
        market: 'ZM',
        stream: 'purchase',
        format: this.earningFormat(title.format),
        note: `Ledger ${settled.journal.id} · ${intent.provider}`,
      });
    }

    const granted = this.library.grant(intent.uid, intent.titleId, { skipEarning: true });
    return {
      ...this.successPayload(intent),
      ownedIds: granted.ownedIds,
      journalId: settled.journal.id,
      allocation: {
        feeMinor: settled.feeMinor,
        netMinor: settled.netMinor,
        creatorShareMinor: settled.creatorShareMinor,
        platformShareMinor: settled.platformShareMinor,
      },
    };
  }

  private initialProviderState(
    provider: PaymentProvider,
    payerPhone?: string,
  ): {
    status: PaymentIntent['status'];
    actionHint?: string;
  } {
    if (provider === 'simulate') {
      return { status: 'requires_confirmation' };
    }
    if (provider === 'mtn_momo' || provider === 'airtel_money') {
      if (!payerPhone?.trim()) {
        throw new BadRequestException('payerPhone is required for mobile money');
      }
      const label = provider === 'mtn_momo' ? 'MTN MoMo' : 'Airtel Money';
      return {
        status: 'requires_action',
        actionHint: `Approve the ${label} prompt on ${payerPhone.trim()}. Sandbox: use Confirm after approving.`,
      };
    }
    return {
      status: 'requires_action',
      actionHint: 'Complete card authentication when prompted. Sandbox: use Confirm after 3-D Secure.',
    };
  }

  private normalizeProvider(raw?: string): PaymentProvider {
    const value = (raw ?? 'simulate').trim().toLowerCase();
    if (value === 'mtn_momo' || value === 'mtn' || value === 'momo') return 'mtn_momo';
    if (value === 'airtel_money' || value === 'airtel') return 'airtel_money';
    if (value === 'card' || value === 'visa' || value === 'mastercard') return 'card';
    return 'simulate';
  }

  private publicIntent(intent: PaymentIntent) {
    return {
      id: intent.id,
      kind: intent.kind,
      titleId: intent.titleId,
      planId: intent.planId,
      amountMinor: intent.amountMinor,
      currency: intent.currency,
      status: intent.status,
      provider: intent.provider,
      payerPhone: intent.payerPhone,
      actionHint: intent.actionHint,
      mode: this.mode(),
    };
  }

  private mode(): 'simulate' | 'live' {
    const raw = (process.env.PAYMENTS_MODE ?? 'simulate').toLowerCase();
    return raw === 'live' ? 'live' : 'simulate';
  }

  private successPayload(intent: PaymentIntent) {
    return {
      id: intent.id,
      kind: intent.kind,
      titleId: intent.titleId,
      planId: intent.planId,
      uid: intent.uid,
      status: 'succeeded' as const,
      provider: intent.provider,
    };
  }

  private earningFormat(format: ContentFormat): 'ebook' | 'audiobook' | 'podcast' {
    if (format === 'audiobook' || format === 'ebook_audio') return 'audiobook';
    if (format === 'podcast') return 'podcast';
    return 'ebook';
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
