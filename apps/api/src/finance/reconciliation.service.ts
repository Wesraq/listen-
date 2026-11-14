import {
  BadRequestException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';

import type { LedgerJournal, PaymentProvider } from './finance.types';
import { LedgerStore } from './ledger.store';
import { ReconciliationStore } from './reconciliation.store';
import type {
  ReconciliationException,
  ReconciliationRun,
  SettlementBatch,
  SettlementLine,
  SettlementLineKind,
} from './reconciliation.types';

function sumByKind(lines: SettlementLine[], kind: SettlementLineKind): number {
  return lines
    .filter((l) => l.kind === kind)
    .reduce((s, l) => s + Math.abs(l.amountMinor), 0);
}

function inPeriod(iso: string, start: string, end: string): boolean {
  const t = new Date(iso).getTime();
  return t >= new Date(start).getTime() && t <= new Date(end).getTime();
}

function lineFeeFromJournal(j: LedgerJournal): number {
  return j.lines
    .filter((l) => l.account === 'expense:processing_fees')
    .reduce((s, l) => s + l.debitMinor, 0);
}

function lineGrossFromJournal(j: LedgerJournal): number {
  // Gross ≈ fee + net clearing debit (or sum of credits on revenue+payable).
  const fee = lineFeeFromJournal(j);
  const clearing = j.lines
    .filter((l) => l.account === 'assets:processor_clearing')
    .reduce((s, l) => s + l.debitMinor, 0);
  if (clearing > 0) return clearing + fee;
  return j.lines.reduce((s, l) => s + l.creditMinor, 0);
}

function creatorShareFromJournal(j: LedgerJournal): number {
  return j.lines
    .filter((l) => String(l.account).startsWith('liability:creator_payable'))
    .reduce((s, l) => s + l.creditMinor, 0);
}

function platformShareFromJournal(j: LedgerJournal): number {
  return j.lines
    .filter(
      (l) =>
        l.account === 'revenue:content_sales' ||
        l.account === 'revenue:subscription' ||
        l.account === 'revenue:advertising',
    )
    .reduce((s, l) => s + l.creditMinor, 0);
}

@Injectable()
export class ReconciliationService {
  constructor(
    @Inject(ReconciliationStore) private readonly store: ReconciliationStore,
    @Inject(LedgerStore) private readonly ledger: LedgerStore,
  ) {}

  listBatches() {
    return { items: this.store.listBatches() };
  }

  getBatch(id: string) {
    const batch = this.store.getBatch(id);
    if (!batch) throw new NotFoundException(`Settlement batch ${id} not found`);
    return batch;
  }

  listExceptions(status?: ReconciliationException['status']) {
    return { items: this.store.listExceptions(status) };
  }

  listRuns() {
    return { items: this.store.listRuns() };
  }

  getRun(id: string) {
    const run = this.store.getRun(id);
    if (!run) throw new NotFoundException(`Reconciliation run ${id} not found`);
    return run;
  }

  /**
   * Import a provider / bank settlement statement for a period.
   * Lines are unmatched until `matchBatch` runs.
   */
  importBatch(input: {
    provider: PaymentProvider | 'bank' | 'admob' | string;
    currency?: string;
    periodStart: string;
    periodEnd: string;
    source: string;
    importedBy: string;
    notes?: string;
    lines: Array<{
      kind: SettlementLineKind;
      amountMinor: number;
      currency?: string;
      providerRef: string;
      internalRef?: string;
      occurredAt: string;
      description?: string;
    }>;
  }): SettlementBatch {
    if (!input.periodStart || !input.periodEnd) {
      throw new BadRequestException('periodStart and periodEnd are required');
    }
    if (!input.lines?.length) {
      throw new BadRequestException('At least one settlement line is required');
    }

    const currency = (input.currency || 'ZMW').toUpperCase();
    const lines: SettlementLine[] = input.lines.map((raw) => {
      const providerRef = raw.providerRef?.trim();
      if (!providerRef) throw new BadRequestException('Each line needs providerRef');
      if (!raw.kind) throw new BadRequestException('Each line needs kind');
      return {
        id: `sl_${randomUUID().replace(/-/g, '').slice(0, 16)}`,
        kind: raw.kind,
        amountMinor: Math.floor(raw.amountMinor),
        currency: (raw.currency || currency).toUpperCase(),
        providerRef,
        internalRef: raw.internalRef?.trim() || undefined,
        occurredAt: raw.occurredAt || new Date().toISOString(),
        description: raw.description,
        matchStatus: 'unmatched',
      };
    });

    const batch: SettlementBatch = {
      id: `sb_${randomUUID().replace(/-/g, '').slice(0, 16)}`,
      provider: input.provider,
      currency,
      periodStart: input.periodStart,
      periodEnd: input.periodEnd,
      status: 'draft',
      source: input.source.trim() || 'manual_import',
      importedAt: new Date().toISOString(),
      importedBy: input.importedBy,
      lines,
      totals: {
        customerPaymentsMinor: sumByKind(lines, 'customer_payment'),
        processingFeesMinor: sumByKind(lines, 'processing_fee'),
        bankCreditsMinor: sumByKind(lines, 'bank_credit'),
        creatorPayoutsMinor: sumByKind(lines, 'creator_payout'),
        refundsMinor: sumByKind(lines, 'refund'),
        adjustmentsMinor: sumByKind(lines, 'adjustment'),
      },
      notes: input.notes,
    };
    this.store.saveBatch(batch);
    return batch;
  }

  /**
   * Auto-match settlement lines to ledger journals / cashouts by providerRef
   * and internalRef. Creates exceptions for unmatched material lines.
   */
  matchBatch(batchId: string, actorEmail: string): SettlementBatch {
    const batch = this.getBatch(batchId);
    if (batch.status === 'closed') {
      throw new BadRequestException('Closed batches cannot be re-matched');
    }

    batch.status = 'matching';
    const journals = this.ledger.listJournals().filter((j) => j.currency === batch.currency);
    const cashouts = this.ledger.listCashouts().filter((c) => c.currency === batch.currency);

    for (const line of batch.lines) {
      if (line.matchStatus === 'waived') continue;

      if (line.kind === 'customer_payment' || line.kind === 'processing_fee') {
        const journal = this.findPaymentJournal(journals, line);
        if (!journal) {
          line.matchStatus = 'unmatched';
          line.matchedJournalId = undefined;
          this.openException({
            kind: 'unmatched_settlement_line',
            currency: line.currency,
            amountMinor: Math.abs(line.amountMinor),
            batchId: batch.id,
            lineId: line.id,
            providerRef: line.providerRef,
            message: `Settlement ${line.kind} ${line.providerRef} has no matching payment journal`,
          });
          continue;
        }

        const expected =
          line.kind === 'processing_fee'
            ? lineFeeFromJournal(journal)
            : lineGrossFromJournal(journal);
        const actual = Math.abs(line.amountMinor);
        line.matchedJournalId = journal.id;
        line.matchedAmountMinor = expected;

        if (expected === actual) {
          line.matchStatus = 'matched';
          this.clearLineExceptions(batch.id, line.id);
        } else if (Math.abs(expected - actual) <= 1) {
          // 1 minor rounding tolerance
          line.matchStatus = 'matched';
          this.clearLineExceptions(batch.id, line.id);
        } else {
          line.matchStatus = 'partial';
          this.openException({
            kind: line.kind === 'processing_fee' ? 'fee_variance' : 'amount_mismatch',
            currency: line.currency,
            amountMinor: Math.abs(expected - actual),
            expectedMinor: expected,
            actualMinor: actual,
            batchId: batch.id,
            lineId: line.id,
            journalId: journal.id,
            providerRef: line.providerRef,
            message: `${line.kind} variance for ${line.providerRef}: ledger ${expected} vs statement ${actual}`,
          });
        }
        continue;
      }

      if (line.kind === 'creator_payout') {
        const cashout = cashouts.find(
          (c) =>
            c.providerRef === line.providerRef ||
            c.id === line.internalRef ||
            (line.internalRef && c.id === line.internalRef),
        );
        if (!cashout) {
          line.matchStatus = 'unmatched';
          this.openException({
            kind: 'unmatched_settlement_line',
            currency: line.currency,
            amountMinor: Math.abs(line.amountMinor),
            batchId: batch.id,
            lineId: line.id,
            providerRef: line.providerRef,
            message: `Payout statement line ${line.providerRef} has no matching cashout`,
          });
          continue;
        }
        line.matchedCashoutId = cashout.id;
        const expected = cashout.netMinor;
        const actual = Math.abs(line.amountMinor);
        line.matchedAmountMinor = expected;
        if (expected === actual || Math.abs(expected - actual) <= 1) {
          line.matchStatus = 'matched';
          this.clearLineExceptions(batch.id, line.id);
        } else {
          line.matchStatus = 'partial';
          this.openException({
            kind: 'payout_variance',
            currency: line.currency,
            amountMinor: Math.abs(expected - actual),
            expectedMinor: expected,
            actualMinor: actual,
            batchId: batch.id,
            lineId: line.id,
            cashoutId: cashout.id,
            providerRef: line.providerRef,
            message: `Payout variance ${cashout.id}: ledger net ${expected} vs statement ${actual}`,
          });
        }
        continue;
      }

      if (line.kind === 'bank_credit') {
        // Bank credits are matched at run-level against expected net deposits;
        // mark present for batch completeness.
        line.matchStatus = 'matched';
        line.matchedAmountMinor = Math.abs(line.amountMinor);
        continue;
      }

      // refund / adjustment — require manual review unless internalRef hits a journal
      const journal = line.internalRef
        ? journals.find(
            (j) => j.id === line.internalRef || j.referenceId === line.internalRef,
          )
        : undefined;
      if (journal) {
        line.matchStatus = 'matched';
        line.matchedJournalId = journal.id;
      } else {
        line.matchStatus = 'exception';
        this.openException({
          kind: 'unmatched_settlement_line',
          currency: line.currency,
          amountMinor: Math.abs(line.amountMinor),
          batchId: batch.id,
          lineId: line.id,
          providerRef: line.providerRef,
          message: `${line.kind} line ${line.providerRef} requires manual reconciliation`,
        });
      }
    }

    // Ledger payment confirms in period with no settlement line
    const periodPayments = journals.filter(
      (j) =>
        (j.kind === 'payment_settlement' || j.kind === 'subscription_settlement') &&
        j.cashoutEligible !== false &&
        inPeriod(j.at, batch.periodStart, batch.periodEnd) &&
        (batch.provider === 'bank' ||
          batch.provider === 'admob' ||
          !j.provider ||
          j.provider === batch.provider),
    );
    for (const journal of periodPayments) {
      const matched = batch.lines.some(
        (l) =>
          l.kind === 'customer_payment' &&
          (l.matchedJournalId === journal.id ||
            l.providerRef === journal.providerRef ||
            l.internalRef === journal.referenceId),
      );
      if (!matched) {
        this.openException({
          kind: 'unmatched_payment_confirm',
          currency: journal.currency,
          amountMinor: lineGrossFromJournal(journal),
          batchId: batch.id,
          journalId: journal.id,
          providerRef: journal.providerRef,
          message: `Ledger payment ${journal.referenceId} has no settlement line in batch ${batch.id}`,
        });
      }
    }

    const openForBatch = this.store
      .listExceptions('open')
      .filter((e) => e.batchId === batch.id);
    batch.status = openForBatch.length === 0 ? 'balanced' : 'matching';
    batch.lastMatchAt = new Date().toISOString();
    this.store.saveBatch(batch);
    void actorEmail;
    return batch;
  }

  closeBatch(batchId: string, actorEmail: string, force = false): SettlementBatch {
    const batch = this.getBatch(batchId);
    const open = this.store
      .listExceptions('open')
      .filter((e) => e.batchId === batch.id);
    if (open.length > 0 && !force) {
      throw new BadRequestException(
        `Cannot close batch with ${open.length} open exception(s); resolve/waive or pass force`,
      );
    }
    batch.status = 'closed';
    batch.closedAt = new Date().toISOString();
    batch.closedBy = actorEmail;
    this.store.saveBatch(batch);
    return batch;
  }

  /**
   * Full period reconciliation across the six control points:
   * payment confirms, provider settlements, bank credits, fees,
   * creator liabilities, creator payouts.
   */
  runPeriod(input: {
    currency?: string;
    periodStart: string;
    periodEnd: string;
    batchIds?: string[];
    createdBy: string;
  }): ReconciliationRun {
    if (!input.periodStart || !input.periodEnd) {
      throw new BadRequestException('periodStart and periodEnd are required');
    }
    const currency = (input.currency || 'ZMW').toUpperCase();
    const batches = (
      input.batchIds?.length
        ? input.batchIds.map((id) => this.getBatch(id))
        : this.store
            .listBatches()
            .filter(
              (b) =>
                b.currency === currency &&
                b.periodStart <= input.periodEnd &&
                b.periodEnd >= input.periodStart,
            )
    ).filter((b) => b.currency === currency);

    // Ensure batches are matched before roll-up
    for (const batch of batches) {
      if (batch.status === 'draft') {
        this.matchBatch(batch.id, input.createdBy);
      }
    }

    const journals = this.ledger
      .listJournals()
      .filter((j) => j.currency === currency && j.cashoutEligible !== false);
    const periodJournals = journals.filter((j) =>
      inPeriod(j.at, input.periodStart, input.periodEnd),
    );
    const paymentJournals = periodJournals.filter(
      (j) => j.kind === 'payment_settlement' || j.kind === 'subscription_settlement',
    );

    let ledgerGross = 0;
    let ledgerFee = 0;
    let ledgerCreator = 0;
    let ledgerPlatform = 0;
    for (const j of paymentJournals) {
      ledgerGross += lineGrossFromJournal(j);
      ledgerFee += lineFeeFromJournal(j);
      ledgerCreator += creatorShareFromJournal(j);
      ledgerPlatform += platformShareFromJournal(j);
    }
    const ledgerNet = Math.max(0, ledgerGross - ledgerFee);

    const settlementGross = batches.reduce((s, b) => s + b.totals.customerPaymentsMinor, 0);
    const settlementFee = batches.reduce((s, b) => s + b.totals.processingFeesMinor, 0);
    const settlementBank = batches.reduce((s, b) => s + b.totals.bankCreditsMinor, 0);
    const settlementPayouts = batches.reduce((s, b) => s + b.totals.creatorPayoutsMinor, 0);
    const settlementPaymentCount = batches.reduce(
      (s, b) => s + b.lines.filter((l) => l.kind === 'customer_payment').length,
      0,
    );
    const settlementPayoutCount = batches.reduce(
      (s, b) => s + b.lines.filter((l) => l.kind === 'creator_payout').length,
      0,
    );

    const cashouts = this.ledger.listCashouts().filter((c) => c.currency === currency);
    const settledCashouts = cashouts.filter(
      (c) =>
        c.status === 'settled' &&
        c.settledAt &&
        inPeriod(c.settledAt, input.periodStart, input.periodEnd),
    );
    const ledgerSettledGross = settledCashouts.reduce((s, c) => s + c.amountMinor, 0);
    const ledgerSettledNet = settledCashouts.reduce((s, c) => s + c.netMinor, 0);

    // Creator liability roll-forward (cashoutable journals only)
    const opening = this.payableAsOf(currency, input.periodStart, /* exclusive end */ true);
    const closingComputed = this.payableAsOf(currency, input.periodEnd, false);
    let periodCredits = 0;
    let periodPayoutDebits = 0;
    const payablePrefix = 'liability:creator_payable:';
    for (const j of periodJournals) {
      if (j.kind === 'ad_settlement' && j.cashoutEligible !== true) continue;
      for (const line of j.lines) {
        if (!String(line.account).startsWith(payablePrefix)) continue;
        periodCredits += line.creditMinor;
        periodPayoutDebits += line.debitMinor;
      }
    }
    const closingRoll = opening + periodCredits - periodPayoutDebits;

    const exceptionIds: string[] = [];
    const runId = `rr_${randomUUID().replace(/-/g, '').slice(0, 16)}`;

    const pushEx = (
      partial: Omit<ReconciliationException, 'id' | 'createdAt' | 'updatedAt' | 'status'>,
    ) => {
      if (partial.amountMinor === 0) return;
      const ex = this.openException(partial);
      exceptionIds.push(ex.id);
    };

    pushEx({
      kind: 'amount_mismatch',
      currency,
      amountMinor: Math.abs(ledgerGross - settlementGross),
      expectedMinor: ledgerGross,
      actualMinor: settlementGross,
      message: `Customer payment gross: ledger ${ledgerGross} vs settlements ${settlementGross}`,
    });
    pushEx({
      kind: 'fee_variance',
      currency,
      amountMinor: Math.abs(ledgerFee - settlementFee),
      expectedMinor: ledgerFee,
      actualMinor: settlementFee,
      message: `Processing fees: ledger ${ledgerFee} vs settlements ${settlementFee}`,
    });
    const expectedNetDeposit = Math.max(0, settlementGross - settlementFee);
    pushEx({
      kind: 'bank_credit_variance',
      currency,
      amountMinor: Math.abs(expectedNetDeposit - settlementBank),
      expectedMinor: expectedNetDeposit,
      actualMinor: settlementBank,
      message: `Bank credits: expected net ${expectedNetDeposit} vs statement deposits ${settlementBank}`,
    });
    pushEx({
      kind: 'creator_liability_variance',
      currency,
      amountMinor: Math.abs(closingRoll - closingComputed),
      expectedMinor: closingRoll,
      actualMinor: closingComputed,
      message: `Creator payable roll-forward ${closingRoll} vs computed closing ${closingComputed}`,
    });
    pushEx({
      kind: 'payout_variance',
      currency,
      amountMinor: Math.abs(ledgerSettledNet - settlementPayouts),
      expectedMinor: ledgerSettledNet,
      actualMinor: settlementPayouts,
      message: `Creator payouts: ledger net settled ${ledgerSettledNet} vs statement ${settlementPayouts}`,
    });

    // Include open batch exceptions for this period
    for (const batch of batches) {
      for (const ex of this.store.listExceptions('open')) {
        if (ex.batchId === batch.id && !exceptionIds.includes(ex.id)) {
          exceptionIds.push(ex.id);
        }
      }
    }

    const balanced = exceptionIds.length === 0;
    const run: ReconciliationRun = {
      id: runId,
      currency,
      periodStart: input.periodStart,
      periodEnd: input.periodEnd,
      createdAt: new Date().toISOString(),
      createdBy: input.createdBy,
      status: balanced ? 'balanced' : 'exceptions',
      batchIds: batches.map((b) => b.id),
      customerPayments: {
        ledgerConfirmCount: paymentJournals.length,
        ledgerGrossMinor: ledgerGross,
        ledgerFeeMinor: ledgerFee,
        ledgerNetMinor: ledgerNet,
        ledgerCreatorShareMinor: ledgerCreator,
        ledgerPlatformShareMinor: ledgerPlatform,
        settlementPaymentCount,
        settlementGrossMinor: settlementGross,
        varianceGrossMinor: ledgerGross - settlementGross,
      },
      processingFees: {
        ledgerFeeMinor: ledgerFee,
        settlementFeeMinor: settlementFee,
        varianceMinor: ledgerFee - settlementFee,
      },
      bank: {
        settlementBankCreditMinor: settlementBank,
        expectedNetDepositMinor: expectedNetDeposit,
        varianceMinor: expectedNetDeposit - settlementBank,
      },
      creatorLiabilities: {
        openingPayableMinor: opening,
        periodCreditsMinor: periodCredits,
        periodPayoutDebitsMinor: periodPayoutDebits,
        closingPayableMinor: closingRoll,
        computedClosingMinor: closingComputed,
        varianceMinor: closingRoll - closingComputed,
      },
      creatorPayouts: {
        ledgerSettledCount: settledCashouts.length,
        ledgerSettledGrossMinor: ledgerSettledGross,
        ledgerSettledNetMinor: ledgerSettledNet,
        settlementPayoutCount,
        settlementPayoutMinor: settlementPayouts,
        varianceMinor: ledgerSettledNet - settlementPayouts,
      },
      exceptionIds,
      summary: balanced
        ? `Period ${input.periodStart} → ${input.periodEnd} balanced across payments, fees, bank, liabilities, and payouts.`
        : `Period ${input.periodStart} → ${input.periodEnd} has ${exceptionIds.length} open control exception(s). Do not treat cashouts as production-ready until cleared.`,
    };
    this.store.saveRun(run);
    return run;
  }

  resolveException(input: {
    id: string;
    status: 'resolved' | 'waived' | 'investigating';
    actorEmail: string;
    note?: string;
  }): ReconciliationException {
    const row = this.store.getException(input.id);
    if (!row) throw new NotFoundException(`Exception ${input.id} not found`);
    row.status = input.status;
    row.updatedAt = new Date().toISOString();
    if (input.status === 'resolved' || input.status === 'waived') {
      row.resolvedAt = row.updatedAt;
      row.resolvedBy = input.actorEmail;
      row.resolutionNote = input.note;
    }
    this.store.saveException(row);

    if (
      (input.status === 'resolved' || input.status === 'waived') &&
      row.batchId &&
      row.lineId
    ) {
      const batch = this.store.getBatch(row.batchId);
      const line = batch?.lines.find((l) => l.id === row.lineId);
      if (batch && line && input.status === 'waived') {
        line.matchStatus = 'waived';
        line.exceptionId = row.id;
        this.store.saveBatch(batch);
      }
    }
    return row;
  }

  /** Dashboard snapshot for admin Finance. */
  overview(currency = 'ZMW') {
    const openExceptions = this.store.listExceptions('open');
    const batches = this.store.listBatches().filter((b) => b.currency === currency);
    const runs = this.store.listRuns().filter((r) => r.currency === currency);
    const latestRun = runs[0] ?? null;
    return {
      currency,
      openExceptionCount: openExceptions.length,
      draftBatchCount: batches.filter((b) => b.status === 'draft').length,
      matchingBatchCount: batches.filter((b) => b.status === 'matching').length,
      balancedBatchCount: batches.filter((b) => b.status === 'balanced').length,
      closedBatchCount: batches.filter((b) => b.status === 'closed').length,
      latestRun,
      controls: [
        'customer_payment_confirms',
        'provider_settlement_reports',
        'bank_credits',
        'processing_fees',
        'creator_liabilities',
        'creator_payouts',
      ],
      goLiveGate:
        openExceptions.length === 0 &&
        latestRun?.status === 'balanced' &&
        batches.some((b) => b.status === 'closed' || b.status === 'balanced'),
    };
  }

  private findPaymentJournal(
    journals: LedgerJournal[],
    line: SettlementLine,
  ): LedgerJournal | undefined {
    return journals.find((j) => {
      if (j.kind !== 'payment_settlement' && j.kind !== 'subscription_settlement') {
        return false;
      }
      if (line.internalRef && (j.referenceId === line.internalRef || j.id === line.internalRef)) {
        return true;
      }
      if (line.providerRef && j.providerRef === line.providerRef) return true;
      return false;
    });
  }

  private payableAsOf(currency: string, asOfIso: string, exclusive: boolean): number {
    const asOf = new Date(asOfIso).getTime();
    const balances = new Map<string, number>();
    for (const journal of this.ledger.listJournals()) {
      if (journal.currency !== currency) continue;
      if (journal.cashoutEligible === false) continue;
      if (journal.kind === 'ad_settlement' && journal.cashoutEligible !== true) continue;
      const t = new Date(journal.at).getTime();
      if (exclusive ? t >= asOf : t > asOf) continue;
      for (const line of journal.lines) {
        if (!String(line.account).startsWith('liability:creator_payable:')) continue;
        const prev = balances.get(line.account) ?? 0;
        balances.set(line.account, prev + line.creditMinor - line.debitMinor);
      }
    }
    let total = 0;
    for (const v of balances.values()) total += Math.max(0, v);
    return total;
  }

  private openException(
    partial: Omit<ReconciliationException, 'id' | 'createdAt' | 'updatedAt' | 'status'>,
  ): ReconciliationException {
    // Dedupe open exceptions with same identity (batch line or period control).
    const existing = this.store.listExceptions('open').find((e) => {
      if (e.kind !== partial.kind) return false;
      if (partial.batchId || partial.lineId || partial.journalId || partial.cashoutId) {
        return (
          e.batchId === partial.batchId &&
          e.lineId === partial.lineId &&
          e.journalId === partial.journalId &&
          e.cashoutId === partial.cashoutId &&
          e.providerRef === partial.providerRef
        );
      }
      return e.currency === partial.currency && e.message === partial.message;
    });
    if (existing) {
      existing.amountMinor = partial.amountMinor;
      existing.expectedMinor = partial.expectedMinor;
      existing.actualMinor = partial.actualMinor;
      existing.message = partial.message;
      existing.updatedAt = new Date().toISOString();
      this.store.saveException(existing);
      return existing;
    }
    const now = new Date().toISOString();
    const row: ReconciliationException = {
      ...partial,
      id: `rx_${randomUUID().replace(/-/g, '').slice(0, 16)}`,
      status: 'open',
      createdAt: now,
      updatedAt: now,
    };
    this.store.saveException(row);
    return row;
  }

  private clearLineExceptions(batchId: string, lineId: string) {
    for (const ex of this.store.listExceptions('open')) {
      if (ex.batchId === batchId && ex.lineId === lineId) {
        ex.status = 'resolved';
        ex.resolvedAt = new Date().toISOString();
        ex.resolvedBy = 'auto:match';
        ex.resolutionNote = 'Cleared by successful auto-match';
        ex.updatedAt = ex.resolvedAt;
        this.store.saveException(ex);
      }
    }
  }
}
