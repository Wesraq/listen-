const API_BASE = import.meta.env.VITE_API_BASE ?? '';

export type AdminUser = {
  id: string;
  email: string;
  displayName: string;
  role: string;
};

export class AdminApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = 'AdminApiError';
  }

  get isUnauthorized() {
    return this.status === 401;
  }
}

async function request<T>(path: string, init: RequestInit = {}, token?: string): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set('Content-Type', 'application/json');
  if (token) headers.set('Authorization', `Bearer ${token}`);
  let response: Response;
  try {
    response = await fetch(`${API_BASE}${path}`, { ...init, headers });
  } catch {
    throw new AdminApiError(
      'Cannot reach Listen+ API. Start apps/api on port 3001, then retry.',
      0,
    );
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const proxyHint =
      response.status === 500 || response.status === 502 || response.status === 504
        ? ' (often means the API on :3001 is down — start apps/api)'
        : '';
    throw new AdminApiError(
      `${(data as { message?: string }).message ?? `Request failed (${response.status})`}${proxyHint}`,
      response.status,
    );
  }
  return data as T;
}

export function login(email: string, password: string) {
  return request<{
    token: string;
    admin: AdminUser;
    expiresAt: string;
  }>('/v1/admin/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
}

export function getOverview(token: string) {
  return request<{
    pendingCreators: number;
    moderationQueue: number;
    payoutQueue: number;
    paymentExceptions: number;
    users: number;
    market: { code: string; currency: string };
    adSettlements?: number;
    advertisingRevenueMinor?: number;
    reconciliationOpenExceptions?: number;
    reconciliationGoLiveGate?: boolean;
    reconciliationLatestRunStatus?: string | null;
  }>('/v1/admin/overview', {}, token);
}

export function getReconciliationOverview(token: string) {
  return request<{
    currency: string;
    openExceptionCount: number;
    draftBatchCount: number;
    matchingBatchCount: number;
    balancedBatchCount: number;
    closedBatchCount: number;
    goLiveGate: boolean;
    latestRun: {
      id: string;
      status: string;
      periodStart: string;
      periodEnd: string;
      summary: string;
      customerPayments: Record<string, number>;
      processingFees: Record<string, number>;
      bank: Record<string, number>;
      creatorLiabilities: Record<string, number>;
      creatorPayouts: Record<string, number>;
    } | null;
    controls: string[];
  }>('/v1/admin/reconciliation/overview', {}, token);
}

export function getReconciliationExceptions(token: string) {
  return request<{
    items: Array<{
      id: string;
      kind: string;
      status: string;
      currency: string;
      amountMinor: number;
      message: string;
      createdAt: string;
    }>;
  }>('/v1/admin/reconciliation/exceptions', {}, token);
}

export function runReconciliation(
  token: string,
  body: { periodStart: string; periodEnd: string; currency?: string },
) {
  return request('/v1/admin/reconciliation/runs', {
    method: 'POST',
    body: JSON.stringify(body),
  }, token);
}

export function resolveReconciliationException(
  token: string,
  id: string,
  status: 'resolved' | 'waived' | 'investigating',
  note?: string,
) {
  return request(`/v1/admin/reconciliation/exceptions/${encodeURIComponent(id)}/resolve`, {
    method: 'POST',
    body: JSON.stringify({ status, note }),
  }, token);
}

export function getAdSettlements(token: string) {
  return request<{
    items: Array<{
      id: string;
      at: string;
      currency: string;
      titleId: string;
      creatorUid: string;
      customerUid: string;
      referenceId: string;
      grossMinor: number;
      creatorShareMinor: number;
      platformShareMinor: number;
    }>;
  }>('/v1/admin/ads', {}, token);
}

export type AdminUserListItem = {
  uid: string;
  email: string;
  displayName: string;
  market: string;
  role: string;
  creatorStatus: string;
  createdAt: string;
  draftsCount?: number;
  submittedCount?: number;
  liveCount?: number;
  ownedCount?: number;
  savedCount?: number;
  grossSalesMinor?: number;
  salesCurrency?: string;
};

export type AdminUserProfile = {
  profile: {
    uid: string;
    email: string;
    displayName: string;
    market: string;
    role: string;
    creatorStatus: string;
    createdAt: string;
  };
  library: {
    ownedIds: string[];
    savedIds: string[];
    ownedCount: number;
    savedCount: number;
  };
  studio: {
    drafts: Array<{
      id: string;
      title: string;
      format: string;
      status: string;
      priceLabel: string;
      mediaName?: string;
      publishedTitleId?: string;
      createdAt: string;
      updatedAt: string;
    }>;
    draftsCount: number;
    submittedCount: number;
    liveCount: number;
  };
  sales: {
    currency: string;
    grossSalesMinor: number;
    availableMinor: number;
    pendingMinor: number;
    recent: Array<Record<string, string | number>>;
  };
  moderation: Array<Record<string, string>>;
};

export function getUsers(token: string) {
  return request<{ items: AdminUserListItem[] }>('/v1/admin/users', {}, token);
}

export function getUserProfile(token: string, uid: string) {
  return request<AdminUserProfile>(`/v1/admin/users/${encodeURIComponent(uid)}`, {}, token);
}

export function setCreatorStatus(token: string, uid: string, status: string, reason?: string) {
  return request(`/v1/admin/users/${uid}/creator-status`, {
    method: 'POST',
    body: JSON.stringify({ status, reason }),
  }, token);
}

export function getModeration(token: string) {
  return request<{ items: Array<Record<string, string>> }>('/v1/admin/moderation', {}, token);
}

export function decideModeration(token: string, id: string, status: string, notes?: string) {
  return request(`/v1/admin/moderation/${id}/decision`, {
    method: 'POST',
    body: JSON.stringify({ status, notes }),
  }, token);
}

export function getPayouts(token: string) {
  return request<{ items: Array<Record<string, string | number>> }>('/v1/admin/payouts', {}, token);
}

export function decidePayout(
  token: string,
  id: string,
  status:
    | 'approved'
    | 'processing'
    | 'provider_confirmed'
    | 'settled'
    | 'rejected'
    | 'failed',
  reference?: string,
) {
  return request(`/v1/admin/payouts/${id}/decision`, {
    method: 'POST',
    body: JSON.stringify({ status, reference }),
  }, token);
}

export function getAudit(token: string) {
  return request<{ items: Array<Record<string, string>> }>('/v1/admin/audit', {}, token);
}
