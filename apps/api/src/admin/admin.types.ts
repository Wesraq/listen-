export type AdminRole = 'admin' | 'finance' | 'moderator';

export interface AdminAccount {
  id: string;
  email: string;
  displayName: string;
  role: AdminRole;
  password: string;
}

export interface AdminSession {
  token: string;
  admin: Omit<AdminAccount, 'password'>;
  expiresAt: string;
}

export interface AdminUserRow {
  uid: string;
  email: string;
  displayName: string;
  market: string;
  role: 'listener' | 'creator' | 'admin';
  creatorStatus: 'none' | 'pending' | 'approved' | 'rejected';
  createdAt: string;
}

export interface ModerationItem {
  id: string;
  title: string;
  creatorName: string;
  format: string;
  status: 'submitted' | 'in_review' | 'changes_requested' | 'approved' | 'rejected';
  submittedAt: string;
  notes?: string;
  /** Studio draft id when this queue item came from Creator Studio. */
  draftId?: string;
  creatorUid?: string;
  publishedTitleId?: string;
  /** Human-readable prices from the Studio draft, e.g. "ZMW 85.00 · USD 4.99". */
  priceLabel?: string;
  mediaName?: string;
}

export interface PayoutRequest {
  id: string;
  creatorName: string;
  amountMinor: number;
  currency: string;
  status:
    | 'requested'
    | 'approved'
    | 'processing'
    | 'provider_confirmed'
    | 'settled'
    | 'failed'
    | 'reversed'
    | 'rejected';
  requestedAt: string;
  reference?: string;
}

export interface AuditEntry {
  id: string;
  actorEmail: string;
  action: string;
  target: string;
  at: string;
  reason?: string;
}
