/** Payment rails Listen+ will settle through (sandbox adapters until live keys). */
export type PaymentProvider = 'simulate' | 'mtn_momo' | 'airtel_money' | 'card';

export type PaymentKind = 'title_purchase' | 'subscription';

/** Chart-of-accounts style codes. Creator payables are `liability:creator_payable:{uid}`. */
export type SystemAccountCode =
  | 'assets:processor_clearing'
  | 'assets:platform_cash'
  | 'liability:unallocated_receipts'
  | 'liability:subscription_deferred'
  | 'liability:creator_pool'
  | 'revenue:content_sales'
  | 'revenue:subscription'
  | 'revenue:advertising'
  | 'revenue:payout_fees'
  | 'expense:processing_fees'
  | 'expense:refunds'
  | 'expense:payout_fees';

export type LedgerAccountCode = SystemAccountCode | `liability:creator_payable:${string}`;

export type LedgerEntryKind =
  | 'payment_settlement'
  | 'subscription_settlement'
  | 'creator_earning'
  | 'refund'
  | 'payout'
  | 'ad_settlement'
  | 'adjustment';

export interface LedgerLine {
  account: LedgerAccountCode;
  /** Positive integer in minor currency units. */
  debitMinor: number;
  creditMinor: number;
  memo?: string;
}

export interface LedgerJournal {
  id: string;
  kind: LedgerEntryKind;
  currency: string;
  /** ISO timestamp. */
  at: string;
  /** External correlation (payment intent, payout id, ad event). */
  referenceType: string;
  referenceId: string;
  memo?: string;
  lines: LedgerLine[];
  /** Denormalised parties for reporting. */
  customerUid?: string;
  creatorUid?: string;
  titleId?: string;
  provider?: PaymentProvider;
  providerRef?: string;
}

export interface AccountBalance {
  account: LedgerAccountCode;
  currency: string;
  /** Debits − credits for asset/expense; credits − debits for liability/revenue. */
  balanceMinor: number;
}

export interface CreatorBalanceSnapshot {
  creatorUid: string;
  currency: string;
  /** Gross credits posted to creator payable. */
  earnedMinor: number;
  /** Debits against payable (cashouts). */
  paidOutMinor: number;
  /** earned − paidOut (before holds / in-flight requests). */
  payableMinor: number;
  /** Earnings still inside the hold window. */
  pendingHoldMinor: number;
  /** Cashout requests not yet settled/rejected. */
  inFlightMinor: number;
  /** Max that can be requested now. */
  availableMinor: number;
  /** Hold window used for pendingHoldMinor. */
  holdDays: number;
  minPayoutMinor: number;
}

export type CashoutRail = 'mtn_momo' | 'airtel_money' | 'bank';

export type CashoutStatus =
  | 'requested'
  | 'approved'
  | 'rejected'
  | 'settled'
  | 'failed';

export interface CashoutRequest {
  id: string;
  creatorUid: string;
  creatorEmail?: string;
  creatorName: string;
  amountMinor: number;
  /** Fee deducted from the creator’s payout (posted on settle). */
  feeMinor: number;
  /** Net sent to the creator rail. */
  netMinor: number;
  currency: string;
  rail: CashoutRail;
  /** MSISDN or bank account reference. */
  destination: string;
  status: CashoutStatus;
  requestedAt: string;
  updatedAt: string;
  decidedAt?: string;
  decidedBy?: string;
  providerRef?: string;
  failureReason?: string;
  journalId?: string;
}

export interface SubscriptionPlan {
  id: string;
  name: string;
  currency: string;
  amountMinor: number;
  interval: 'month' | 'year';
  /** Markets where this plan is offered. */
  markets: string[];
}

export interface Subscription {
  id: string;
  uid: string;
  planId: string;
  status: 'active' | 'past_due' | 'cancelled' | 'expired';
  provider: PaymentProvider;
  currentPeriodStart: string;
  currentPeriodEnd: string;
  cancelAtPeriodEnd: boolean;
  createdAt: string;
  updatedAt: string;
  lastPaymentIntentId?: string;
}

export function creatorPayableAccount(creatorUid: string): LedgerAccountCode {
  return `liability:creator_payable:${creatorUid}`;
}

export function isDebitNormal(account: LedgerAccountCode): boolean {
  return account.startsWith('assets:') || account.startsWith('expense:');
}
