import type { PaymentProvider } from './finance.types';

/** External statement line categories we reconcile against the ledger. */
export type SettlementLineKind =
  | 'customer_payment'
  | 'processing_fee'
  | 'bank_credit'
  | 'creator_payout'
  | 'refund'
  | 'adjustment';

export type SettlementLineMatchStatus =
  | 'unmatched'
  | 'matched'
  | 'partial'
  | 'exception'
  | 'waived';

export type SettlementBatchStatus = 'draft' | 'matching' | 'balanced' | 'closed';

export type ReconciliationExceptionKind =
  | 'unmatched_payment_confirm'
  | 'unmatched_settlement_line'
  | 'fee_variance'
  | 'bank_credit_variance'
  | 'creator_liability_variance'
  | 'payout_variance'
  | 'amount_mismatch';

export type ReconciliationExceptionStatus = 'open' | 'investigating' | 'resolved' | 'waived';

export interface SettlementLine {
  id: string;
  kind: SettlementLineKind;
  /** Signed: credits to Listen+ positive; fees/payouts often negative on statements. */
  amountMinor: number;
  currency: string;
  /** Provider transaction / MoMo / bank reference. */
  providerRef: string;
  /** Optional Listen+ payment intent or cashout id if known on the statement. */
  internalRef?: string;
  occurredAt: string;
  description?: string;
  matchStatus: SettlementLineMatchStatus;
  matchedJournalId?: string;
  matchedCashoutId?: string;
  matchedAmountMinor?: number;
  exceptionId?: string;
}

export interface SettlementBatch {
  id: string;
  provider: PaymentProvider | 'bank' | 'admob' | string;
  currency: string;
  periodStart: string;
  periodEnd: string;
  status: SettlementBatchStatus;
  source: string;
  importedAt: string;
  importedBy: string;
  lines: SettlementLine[];
  totals: {
    customerPaymentsMinor: number;
    processingFeesMinor: number;
    bankCreditsMinor: number;
    creatorPayoutsMinor: number;
    refundsMinor: number;
    adjustmentsMinor: number;
  };
  notes?: string;
  closedAt?: string;
  closedBy?: string;
  lastMatchAt?: string;
}

export interface ReconciliationException {
  id: string;
  kind: ReconciliationExceptionKind;
  status: ReconciliationExceptionStatus;
  currency: string;
  amountMinor: number;
  expectedMinor?: number;
  actualMinor?: number;
  batchId?: string;
  lineId?: string;
  journalId?: string;
  cashoutId?: string;
  providerRef?: string;
  message: string;
  createdAt: string;
  updatedAt: string;
  resolvedAt?: string;
  resolvedBy?: string;
  resolutionNote?: string;
}

/**
 * Period roll-forward comparing ledger truth to external evidence.
 * This is the pre-live control that must pass before cashouts go to production rails.
 */
export interface ReconciliationRun {
  id: string;
  currency: string;
  periodStart: string;
  periodEnd: string;
  createdAt: string;
  createdBy: string;
  status: 'open' | 'balanced' | 'exceptions' | 'closed';
  batchIds: string[];

  customerPayments: {
    ledgerConfirmCount: number;
    ledgerGrossMinor: number;
    ledgerFeeMinor: number;
    ledgerNetMinor: number;
    ledgerCreatorShareMinor: number;
    ledgerPlatformShareMinor: number;
    settlementPaymentCount: number;
    settlementGrossMinor: number;
    varianceGrossMinor: number;
  };

  processingFees: {
    ledgerFeeMinor: number;
    settlementFeeMinor: number;
    varianceMinor: number;
  };

  bank: {
    settlementBankCreditMinor: number;
    /** Expected clearing release ≈ settlement payments − fees (simplified). */
    expectedNetDepositMinor: number;
    varianceMinor: number;
  };

  creatorLiabilities: {
    openingPayableMinor: number;
    periodCreditsMinor: number;
    periodPayoutDebitsMinor: number;
    closingPayableMinor: number;
    /** Sum of creator payable balances as of periodEnd (cashoutable journals only). */
    computedClosingMinor: number;
    varianceMinor: number;
  };

  creatorPayouts: {
    ledgerSettledCount: number;
    ledgerSettledGrossMinor: number;
    ledgerSettledNetMinor: number;
    settlementPayoutCount: number;
    settlementPayoutMinor: number;
    varianceMinor: number;
  };

  exceptionIds: string[];
  summary: string;
}
