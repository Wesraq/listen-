import {
  BadRequestException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';

import type {
  CashoutRail,
  CashoutRequest,
  CashoutStatus,
  CreatorBalanceSnapshot,
  LedgerAccountCode,
  LedgerEntryKind,
  LedgerJournal,
  LedgerLine,
  PaymentProvider,
  Subscription,
  SubscriptionPlan,
} from './finance.types';
import { processingFeeBpsFor } from '../payments/processing-fees';
import { creatorPayableAccount, isDebitNormal } from './finance.types';
import { LedgerStore } from './ledger.store';

const HOLD_DAYS = 7;
const MIN_PAYOUT_MINOR = 50_00;
/** Flat payout fee in minor units (creator-paid). */
const PAYOUT_FEE_MINOR = 2_00;

const IN_FLIGHT_CASHOUT: CashoutStatus[] = [
  'requested',
  'approved',
  'processing',
  'provider_confirmed',
];

@Injectable()
export class LedgerService {
  constructor(@Inject(LedgerStore) private readonly store: LedgerStore) {}

  listPlans(currency?: string): SubscriptionPlan[] {
    return this.store.listPlans(currency);
  }

  getPlan(planId: string): SubscriptionPlan | undefined {
    return this.store.getPlan(planId);
  }

  getActiveSubscription(uid: string): Subscription | undefined {
    return this.store.getActiveSubscriptionForUser(uid);
  }

  /**
   * Post a balanced journal. Throws if debits ≠ credits or lines are empty.
   * Idempotent on (referenceType, referenceId).
   */
  postJournal(input: {
    kind: LedgerEntryKind;
    currency: string;
    referenceType: string;
    referenceId: string;
    lines: LedgerLine[];
    memo?: string;
    customerUid?: string;
    creatorUid?: string;
    titleId?: string;
    provider?: PaymentProvider;
    providerRef?: string;
    /** Optional ISO timestamp — used when backfilling historical Studio sales. */
    at?: string;
    cashoutEligible?: boolean;
    settlementSource?: string;
  }): LedgerJournal {
    if (this.store.hasSettled(input.referenceType, input.referenceId)) {
      const existing = this.store
        .listJournals()
        .find(
          (j) =>
            j.referenceType === input.referenceType && j.referenceId === input.referenceId,
        );
      if (existing) return existing;
    }

    const lines = input.lines
      .map((line) => ({
        account: line.account,
        debitMinor: Math.max(0, Math.floor(line.debitMinor || 0)),
        creditMinor: Math.max(0, Math.floor(line.creditMinor || 0)),
        memo: line.memo,
      }))
      .filter((line) => line.debitMinor > 0 || line.creditMinor > 0);

    if (!lines.length) {
      throw new BadRequestException('Ledger journal requires at least one non-zero line');
    }
    for (const line of lines) {
      if (line.debitMinor > 0 && line.creditMinor > 0) {
        throw new BadRequestException(`Line ${line.account} cannot debit and credit together`);
      }
    }

    const debit = lines.reduce((sum, l) => sum + l.debitMinor, 0);
    const credit = lines.reduce((sum, l) => sum + l.creditMinor, 0);
    if (debit !== credit) {
      throw new BadRequestException(
        `Unbalanced journal: debit ${debit} ≠ credit ${credit} (${input.currency})`,
      );
    }

    const at =
      input.at && !Number.isNaN(Date.parse(input.at))
        ? new Date(input.at).toISOString()
        : new Date().toISOString();

    const journal: LedgerJournal = {
      id: `je_${randomUUID().replace(/-/g, '').slice(0, 20)}`,
      kind: input.kind,
      currency: input.currency,
      at,
      referenceType: input.referenceType,
      referenceId: input.referenceId,
      memo: input.memo,
      lines,
      customerUid: input.customerUid,
      creatorUid: input.creatorUid,
      titleId: input.titleId,
      provider: input.provider,
      providerRef: input.providerRef,
      cashoutEligible: input.cashoutEligible !== false,
      settlementSource: input.settlementSource,
    };
    this.store.appendJournal(journal);
    return journal;
  }

  /**
   * Settle a verified content purchase into the shared Listen+ ledger.
   * Fee-then-split: processing fee → remaining net → creator / platform shares.
   */
  settleTitlePurchase(input: {
    intentId: string;
    customerUid: string;
    creatorUid?: string;
    titleId: string;
    currency: string;
    grossMinor: number;
    provider: PaymentProvider;
    providerRef?: string;
    /** Basis points of gross taken as processing fee before royalty split. */
    processingFeeBps?: number;
    /** Creator share of net receipts (default 70%). */
    creatorShareBps?: number;
  }): {
    journal: LedgerJournal;
    created: boolean;
    feeMinor: number;
    netMinor: number;
    creatorShareMinor: number;
    platformShareMinor: number;
  } {
    const gross = Math.max(0, Math.floor(input.grossMinor));
    const feeBps = input.processingFeeBps ?? processingFeeBpsFor(input.provider);
    const creatorBps = input.creatorShareBps ?? 7000;
    const feeMinor = Math.floor((gross * feeBps) / 10_000);
    const netMinor = Math.max(0, gross - feeMinor);
    const creatorShareMinor = input.creatorUid
      ? Math.floor((netMinor * creatorBps) / 10_000)
      : 0;
    const platformShareMinor = Math.max(0, netMinor - creatorShareMinor);

    if (this.store.hasSettled('payment_intent', input.intentId)) {
      const existing = this.store
        .listJournals()
        .find(
          (j) =>
            j.referenceType === 'payment_intent' && j.referenceId === input.intentId,
        );
      if (existing) {
        return {
          journal: existing,
          created: false,
          feeMinor,
          netMinor,
          creatorShareMinor,
          platformShareMinor,
        };
      }
    }

    const lines: LedgerLine[] = [
      {
        account: 'assets:processor_clearing',
        debitMinor: Math.max(0, gross - feeMinor),
        creditMinor: 0,
        memo: 'Net processor settlement',
      },
      {
        account: 'expense:processing_fees',
        debitMinor: feeMinor,
        creditMinor: 0,
        memo: `Processing ${feeBps / 100}%`,
      },
      {
        account: 'revenue:content_sales',
        debitMinor: 0,
        creditMinor: platformShareMinor,
        memo: 'Platform share of purchase',
      },
    ];
    if (creatorShareMinor > 0 && input.creatorUid) {
      lines.push({
        account: creatorPayableAccount(input.creatorUid),
        debitMinor: 0,
        creditMinor: creatorShareMinor,
        memo: 'Creator royalty (purchase)',
      });
    }

    // If fee is 0 and creator is missing, entire net is platform revenue — already covered.
    // If gross is 0, postJournal will reject empty — callers should skip free titles.

    const journal = this.postJournal({
      kind: 'payment_settlement',
      currency: input.currency,
      referenceType: 'payment_intent',
      referenceId: input.intentId,
      lines,
      memo: `Title purchase ${input.titleId}`,
      customerUid: input.customerUid,
      creatorUid: input.creatorUid,
      titleId: input.titleId,
      provider: input.provider,
      providerRef: input.providerRef,
      cashoutEligible: true,
      settlementSource: 'payment',
    });

    return {
      journal,
      created: true,
      feeMinor,
      netMinor,
      creatorShareMinor,
      platformShareMinor,
    };
  }

  /**
   * Settle a verified subscription payment.
   * Net after fee: 60% creator pool liability, 40% subscription revenue (policy v1).
   */
  settleSubscription(input: {
    intentId: string;
    customerUid: string;
    planId: string;
    currency: string;
    grossMinor: number;
    provider: PaymentProvider;
    providerRef?: string;
    processingFeeBps?: number;
    creatorPoolBps?: number;
  }): {
    journal: LedgerJournal;
    created: boolean;
    subscription: Subscription;
    feeMinor: number;
    netMinor: number;
    creatorPoolMinor: number;
    platformShareMinor: number;
  } {
    const plan = this.store.getPlan(input.planId);
    if (!plan) throw new BadRequestException(`Unknown plan ${input.planId}`);

    const gross = Math.max(0, Math.floor(input.grossMinor));
    const feeBps = input.processingFeeBps ?? 300;
    const poolBps = input.creatorPoolBps ?? 6000;
    const feeMinor = Math.floor((gross * feeBps) / 10_000);
    const netMinor = Math.max(0, gross - feeMinor);
    const creatorPoolMinor = Math.floor((netMinor * poolBps) / 10_000);
    const platformShareMinor = Math.max(0, netMinor - creatorPoolMinor);

    const already = this.store.hasSettled('payment_intent', input.intentId);

    const journal = this.postJournal({
      kind: 'subscription_settlement',
      currency: input.currency,
      referenceType: 'payment_intent',
      referenceId: input.intentId,
      lines: [
        {
          account: 'assets:processor_clearing',
          debitMinor: Math.max(0, gross - feeMinor),
          creditMinor: 0,
        },
        {
          account: 'expense:processing_fees',
          debitMinor: feeMinor,
          creditMinor: 0,
        },
        {
          account: 'liability:creator_pool',
          debitMinor: 0,
          creditMinor: creatorPoolMinor,
          memo: 'Subscription creator pool accrual',
        },
        {
          account: 'revenue:subscription',
          debitMinor: 0,
          creditMinor: platformShareMinor,
        },
      ],
      memo: `Subscription ${plan.id}`,
      customerUid: input.customerUid,
      provider: input.provider,
      providerRef: input.providerRef,
    });

    const now = new Date();
    const periodEnd = new Date(now);
    if (plan.interval === 'year') periodEnd.setFullYear(periodEnd.getFullYear() + 1);
    else periodEnd.setMonth(periodEnd.getMonth() + 1);

    const existing = this.store.getActiveSubscriptionForUser(input.customerUid);
    const subscription: Subscription = {
      id: existing?.id ?? `sub_${randomUUID().replace(/-/g, '').slice(0, 16)}`,
      uid: input.customerUid,
      planId: plan.id,
      status: 'active',
      provider: input.provider,
      currentPeriodStart: now.toISOString(),
      currentPeriodEnd: periodEnd.toISOString(),
      cancelAtPeriodEnd: false,
      createdAt: existing?.createdAt ?? now.toISOString(),
      updatedAt: now.toISOString(),
      lastPaymentIntentId: input.intentId,
    };
    this.store.saveSubscription(subscription);

    return {
      journal,
      created: !already,
      subscription,
      feeMinor,
      netMinor,
      creatorPoolMinor,
      platformShareMinor,
    };
  }

  /**
   * Settle a verified ad completion.
   * Default split: 55% creator / 45% platform of attributed gross.
   * Simulated AdMob fixed gross posts with cashoutEligible=false until
   * network receipts are reconciled.
   */
  settleAdvertising(input: {
    referenceId: string;
    customerUid: string;
    creatorUid: string;
    titleId: string;
    currency: string;
    grossMinor: number;
    creatorShareBps?: number;
    campaignId?: string;
    placement?: string;
    /** false for prototype AD_GROSS / SSV-simulated amounts. */
    cashoutEligible?: boolean;
    settlementSource?: string;
  }): {
    journal: LedgerJournal;
    created: boolean;
    creatorShareMinor: number;
    platformShareMinor: number;
    cashoutEligible: boolean;
  } {
    const gross = Math.max(0, Math.floor(input.grossMinor));
    const creatorBps = input.creatorShareBps ?? 5500;
    const creatorShareMinor = Math.floor((gross * creatorBps) / 10_000);
    const platformShareMinor = Math.max(0, gross - creatorShareMinor);
    const cashoutEligible = input.cashoutEligible === true;

    if (this.store.hasSettled('ad_completion', input.referenceId)) {
      const existing = this.store
        .listJournals()
        .find(
          (j) =>
            j.referenceType === 'ad_completion' && j.referenceId === input.referenceId,
        );
      if (existing) {
        return {
          journal: existing,
          created: false,
          creatorShareMinor,
          platformShareMinor,
          cashoutEligible: existing.cashoutEligible !== false,
        };
      }
    }

    if (gross <= 0) {
      throw new BadRequestException('Ad gross must be positive');
    }

    const lines: LedgerLine[] = [
      {
        account: 'assets:processor_clearing',
        debitMinor: gross,
        creditMinor: 0,
        memo: cashoutEligible
          ? input.campaignId
            ? `Ad network receipt · ${input.campaignId}`
            : 'Ad network receipt'
          : `SIMULATED ad gross · ${input.campaignId ?? 'network'} (not cashoutable)`,
      },
    ];
    if (creatorShareMinor > 0) {
      lines.push({
        account: creatorPayableAccount(input.creatorUid),
        debitMinor: 0,
        creditMinor: creatorShareMinor,
        memo: cashoutEligible
          ? `Creator ad share · ${input.placement ?? 'ad'}`
          : `SIMULATED creator ad share · ${input.placement ?? 'ad'}`,
      });
    }
    if (platformShareMinor > 0) {
      lines.push({
        account: 'revenue:advertising',
        debitMinor: 0,
        creditMinor: platformShareMinor,
        memo: cashoutEligible ? 'Platform ad share' : 'SIMULATED platform ad share',
      });
    }

    const journal = this.postJournal({
      kind: 'ad_settlement',
      currency: input.currency,
      referenceType: 'ad_completion',
      referenceId: input.referenceId,
      lines,
      memo: cashoutEligible
        ? `Ad completion ${input.titleId}`
        : `SIMULATED ad completion ${input.titleId}`,
      customerUid: input.customerUid,
      creatorUid: input.creatorUid,
      titleId: input.titleId,
      cashoutEligible,
      settlementSource: input.settlementSource ?? (cashoutEligible ? 'ad_reconciled' : 'ssv_simulated'),
    });

    return {
      journal,
      created: true,
      creatorShareMinor,
      platformShareMinor,
      cashoutEligible,
    };
  }

  /**
   * Post a Studio sale line that never hit the shared ledger (legacy grants,
   * subscription pool, pre-ledger ads). Skips rows already mirrored via payment/ad
   * settlement (note contains "ledger") or already posted under studio_sale.
   */
  settleStudioSale(input: {
    saleId: string;
    creatorUid: string;
    titleId?: string;
    currency: string;
    creatorShareMinor: number;
    platformShareMinor: number;
    stream: 'purchase' | 'subscription_pool' | 'advertising' | string;
    at?: string;
    note?: string;
    /**
     * Migrations and pool estimates default to false — they must not create
     * cashoutable liabilities without reconciled funds.
     */
    cashoutEligible?: boolean;
    settlementSource?: string;
  }): { journal: LedgerJournal; created: boolean } | null {
    const note = (input.note ?? '').toLowerCase();
    // Already mirrored when payments/ads posted the real settlement journal.
    if (/\bledger\b/.test(note)) {
      return null;
    }

    const creatorShare = Math.max(0, Math.floor(input.creatorShareMinor));
    const platformShare = Math.max(0, Math.floor(input.platformShareMinor));
    const gross = creatorShare + platformShare;
    if (gross <= 0 || !input.creatorUid) return null;
    const cashoutEligible = input.cashoutEligible === true;

    if (this.store.hasSettled('studio_sale', input.saleId)) {
      const existing = this.store
        .listJournals()
        .find(
          (j) => j.referenceType === 'studio_sale' && j.referenceId === input.saleId,
        );
      if (existing) return { journal: existing, created: false };
    }

    const revenueAccount: LedgerAccountCode =
      input.stream === 'advertising'
        ? 'revenue:advertising'
        : input.stream === 'subscription_pool'
          ? 'revenue:subscription'
          : 'revenue:content_sales';

    const lines: LedgerLine[] = [
      {
        account: 'assets:processor_clearing',
        debitMinor: gross,
        creditMinor: 0,
        memo: cashoutEligible
          ? `Studio sale ${input.stream}`
          : `NON-CASHOUTABLE studio/pool line · ${input.stream}`,
      },
    ];
    if (creatorShare > 0) {
      lines.push({
        account: creatorPayableAccount(input.creatorUid),
        debitMinor: 0,
        creditMinor: creatorShare,
        memo: cashoutEligible
          ? 'Creator share'
          : 'NON-CASHOUTABLE creator share (migration/estimate)',
      });
    }
    if (platformShare > 0) {
      lines.push({
        account: revenueAccount,
        debitMinor: 0,
        creditMinor: platformShare,
        memo: 'Platform share',
      });
    }

    const journal = this.postJournal({
      kind: 'creator_earning',
      currency: input.currency,
      referenceType: 'studio_sale',
      referenceId: input.saleId,
      lines,
      memo: input.note || `Studio sale ${input.saleId}`,
      creatorUid: input.creatorUid,
      titleId: input.titleId,
      at: input.at,
      cashoutEligible,
      settlementSource: input.settlementSource ?? 'studio_migration',
    });

    return { journal, created: true };
  }

  /**
   * Admin-only migration helper. Never call from GET handlers.
   * Defaults to cashoutEligible=false unless explicitly opted in.
   */
  backfillStudioSales(
    sales: Array<{
      id: string;
      creatorUid: string;
      titleId?: string;
      currency: string;
      creatorShareMinor: number;
      platformShareMinor: number;
      stream: string;
      at?: string;
      note?: string;
    }>,
    options?: { cashoutEligible?: boolean },
  ): { posted: number; skipped: number; cashoutEligible: boolean } {
    const cashoutEligible = options?.cashoutEligible === true;
    let posted = 0;
    let skipped = 0;
    for (const sale of sales) {
      const result = this.settleStudioSale({
        saleId: sale.id,
        creatorUid: sale.creatorUid,
        titleId: sale.titleId,
        currency: sale.currency,
        creatorShareMinor: sale.creatorShareMinor,
        platformShareMinor: sale.platformShareMinor,
        stream: sale.stream,
        at: sale.at,
        note: sale.note,
        cashoutEligible,
        settlementSource: 'studio_migration',
      });
      if (!result) skipped += 1;
      else if (result.created) posted += 1;
      else skipped += 1;
    }
    return { posted, skipped, cashoutEligible };
  }

  /** Recent advertising settlements for ops / Studio cross-check. */
  listAdSettlements(limit = 50) {
    return this.store
      .listJournals()
      .filter((j) => j.kind === 'ad_settlement')
      .slice(0, Math.max(1, Math.min(limit, 200)))
      .map((j) => {
        const grossMinor =
          j.lines.find((l) => l.account === 'assets:processor_clearing')?.debitMinor ?? 0;
        const platformShareMinor =
          j.lines.find((l) => l.account === 'revenue:advertising')?.creditMinor ?? 0;
        const creatorShareMinor =
          j.lines.find((l) => String(l.account).startsWith('liability:creator_payable'))
            ?.creditMinor ?? 0;
        return {
          id: j.id,
          at: j.at,
          currency: j.currency,
          titleId: j.titleId ?? '',
          creatorUid: j.creatorUid ?? '',
          customerUid: j.customerUid ?? '',
          referenceId: j.referenceId,
          grossMinor,
          creatorShareMinor,
          platformShareMinor,
          cashoutEligible: j.cashoutEligible === true,
          settlementSource: j.settlementSource ?? '',
        };
      });
  }

  balanceFor(account: LedgerAccountCode, currency: string): number {
    let debit = 0;
    let credit = 0;
    for (const journal of this.store.listJournals()) {
      if (journal.currency !== currency) continue;
      for (const line of journal.lines) {
        if (line.account !== account) continue;
        debit += line.debitMinor;
        credit += line.creditMinor;
      }
    }
    return isDebitNormal(account) ? debit - credit : credit - debit;
  }

  creatorBalance(creatorUid: string, currency = 'ZMW'): CreatorBalanceSnapshot {
    const account = creatorPayableAccount(creatorUid);
    let earned = 0;
    let paidOut = 0;
    let pendingHold = 0;
    const holdMs = HOLD_DAYS * 24 * 60 * 60 * 1000;
    const now = Date.now();

    for (const journal of this.store.listJournals()) {
      if (journal.currency !== currency) continue;
      // Simulated / unreconciled journals never feed cashout availability.
      if (journal.cashoutEligible === false) continue;
      // Ad payables require an explicit cashoutable reconcile (not SSV simulate / legacy).
      if (journal.kind === 'ad_settlement' && journal.cashoutEligible !== true) continue;
      const age = now - new Date(journal.at).getTime();
      for (const line of journal.lines) {
        if (line.account !== account) continue;
        earned += line.creditMinor;
        paidOut += line.debitMinor;
        if (line.creditMinor > 0 && age >= 0 && age < holdMs) {
          pendingHold += line.creditMinor;
        }
      }
    }

    const payable = Math.max(0, earned - paidOut);
    const inFlight = this.store
      .listCashouts()
      .filter(
        (c) =>
          c.creatorUid === creatorUid &&
          c.currency === currency &&
          IN_FLIGHT_CASHOUT.includes(c.status),
      )
      .reduce((sum, c) => sum + c.amountMinor, 0);

    const available = Math.max(0, payable - pendingHold - inFlight);

    return {
      creatorUid,
      currency,
      earnedMinor: earned,
      paidOutMinor: paidOut,
      payableMinor: payable,
      pendingHoldMinor: Math.min(pendingHold, payable),
      inFlightMinor: inFlight,
      availableMinor: available,
      holdDays: HOLD_DAYS,
      minPayoutMinor: MIN_PAYOUT_MINOR,
    };
  }

  listCashoutsForCreator(creatorUid: string): CashoutRequest[] {
    return this.store.listCashouts().filter((c) => c.creatorUid === creatorUid);
  }

  listAllCashouts(): CashoutRequest[] {
    return this.store.listCashouts();
  }

  getCashout(id: string): CashoutRequest | undefined {
    return this.store.getCashout(id);
  }

  requestCashout(input: {
    creatorUid: string;
    creatorName: string;
    creatorEmail?: string;
    amountMinor: number;
    currency?: string;
    rail: CashoutRail;
    destination: string;
  }): CashoutRequest {
    const currency = (input.currency || 'ZMW').toUpperCase();
    const amount = Math.floor(input.amountMinor);
    if (amount <= 0) throw new BadRequestException('amountMinor must be positive');

    const destination = input.destination.trim();
    if (!destination) throw new BadRequestException('destination is required');

    const bal = this.creatorBalance(input.creatorUid, currency);
    if (amount < bal.minPayoutMinor) {
      throw new BadRequestException(
        `Minimum payout is ${bal.minPayoutMinor} ${currency} minor units`,
      );
    }
    if (amount > bal.availableMinor) {
      throw new BadRequestException(
        `Requested ${amount} exceeds available ${bal.availableMinor} ${currency}`,
      );
    }

    const feeMinor = Math.min(PAYOUT_FEE_MINOR, Math.max(0, amount - 1));
    const now = new Date().toISOString();
    const row: CashoutRequest = {
      id: `po_${randomUUID().replace(/-/g, '').slice(0, 18)}`,
      creatorUid: input.creatorUid,
      creatorEmail: input.creatorEmail,
      creatorName: input.creatorName.trim() || input.creatorEmail || input.creatorUid,
      amountMinor: amount,
      feeMinor,
      netMinor: Math.max(0, amount - feeMinor),
      currency,
      rail: input.rail,
      destination,
      status: 'requested',
      requestedAt: now,
      updatedAt: now,
    };
    this.store.saveCashout(row);
    return row;
  }

  decideCashout(input: {
    id: string;
    status: Extract<
      CashoutStatus,
      | 'approved'
      | 'processing'
      | 'provider_confirmed'
      | 'settled'
      | 'failed'
      | 'rejected'
      | 'reversed'
    >;
    actorEmail: string;
    providerRef?: string;
    failureReason?: string;
  }): CashoutRequest {
    const row = this.store.getCashout(input.id);
    if (!row) throw new NotFoundException(`Cashout ${input.id} not found`);
    const now = new Date().toISOString();

    if (input.status === 'rejected' || input.status === 'failed') {
      if (row.status === 'settled' || row.status === 'reversed') {
        throw new BadRequestException(`Cannot mark ${input.status} from ${row.status}`);
      }
      row.status = input.status;
      row.failureReason = input.failureReason;
      row.decidedAt = now;
      row.decidedBy = input.actorEmail;
      row.updatedAt = now;
      if (input.providerRef) row.providerRef = input.providerRef;
      this.store.saveCashout(row);
      return row;
    }

    if (input.status === 'approved') {
      if (row.status !== 'requested' && row.status !== 'approved') {
        throw new BadRequestException(`Cannot approve cashout in status ${row.status}`);
      }
      row.status = 'approved';
      row.decidedAt = now;
      row.decidedBy = input.actorEmail;
      row.updatedAt = now;
      if (input.providerRef) row.providerRef = input.providerRef;
      this.store.saveCashout(row);
      return row;
    }

    if (input.status === 'processing') {
      if (row.status !== 'approved' && row.status !== 'processing') {
        throw new BadRequestException(
          `Cashout must be approved before processing (now ${row.status})`,
        );
      }
      // Sandbox rail adapter: record instruction only — no live MoMo/bank send yet.
      row.status = 'processing';
      row.processingAt = now;
      row.decidedBy = input.actorEmail;
      row.updatedAt = now;
      row.providerRef =
        input.providerRef ||
        row.providerRef ||
        `pending_${row.rail}_${row.id.slice(0, 10)}`;
      this.store.saveCashout(row);
      return row;
    }

    if (input.status === 'provider_confirmed') {
      if (row.status !== 'processing' && row.status !== 'provider_confirmed') {
        throw new BadRequestException(
          `Provider confirm requires processing status (now ${row.status})`,
        );
      }
      const providerRef = (input.providerRef || row.providerRef || '').trim();
      if (!providerRef) {
        throw new BadRequestException(
          'providerRef is required to confirm disbursement with the rail',
        );
      }
      row.status = 'provider_confirmed';
      row.providerConfirmed = true;
      row.providerConfirmedAt = now;
      row.providerRef = providerRef;
      row.decidedBy = input.actorEmail;
      row.updatedAt = now;
      this.store.saveCashout(row);
      return row;
    }

    if (input.status === 'reversed') {
      throw new BadRequestException(
        'Cashout reversal journals are not automated yet — handle via finance adjustment',
      );
    }

    // settled — ledger debit only after verified provider confirmation
    if (row.status === 'settled' && row.journalId) return row;
    if (row.status !== 'provider_confirmed' || !row.providerConfirmed) {
      throw new BadRequestException(
        'Cashout may only settle after provider_confirmed with a providerRef',
      );
    }

    const lines: LedgerLine[] = [
      {
        account: creatorPayableAccount(row.creatorUid),
        debitMinor: row.amountMinor,
        creditMinor: 0,
        memo: `Cashout ${row.rail}`,
      },
      {
        account: 'assets:processor_clearing',
        debitMinor: 0,
        creditMinor: row.netMinor,
        memo: 'Net sent to creator rail',
      },
    ];
    if (row.feeMinor > 0) {
      lines.push({
        account: 'revenue:payout_fees',
        debitMinor: 0,
        creditMinor: row.feeMinor,
        memo: 'Payout fee retained by Listen+',
      });
    }

    const journal = this.postJournal({
      kind: 'payout',
      currency: row.currency,
      referenceType: 'cashout',
      referenceId: row.id,
      lines,
      memo: `Creator cashout ${row.id}`,
      creatorUid: row.creatorUid,
      providerRef: input.providerRef || row.providerRef,
      cashoutEligible: true,
      settlementSource: 'payment',
    });

    row.status = 'settled';
    row.journalId = journal.id;
    row.settledAt = now;
    row.providerRef = input.providerRef || row.providerRef;
    row.decidedAt = now;
    row.decidedBy = input.actorEmail;
    row.updatedAt = now;
    this.store.saveCashout(row);
    return row;
  }

  recentJournals(limit = 50): LedgerJournal[] {
    return this.store.listJournals().slice(0, limit);
  }
}
