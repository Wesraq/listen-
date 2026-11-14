import type { PaymentProvider } from '../finance/finance.types';

/**
 * Processing fee basis points of gross, before creator/platform split.
 * Override via env, e.g.:
 *   PROCESSING_FEE_BPS_JSON={"simulate":300,"mtn_momo":250,"airtel_money":250,"card":350}
 *
 * Defaults are provisional prototypes — replace with contracted provider rates
 * and reconcile against settlement statements before production cashouts.
 */
const DEFAULT_FEE_BPS: Record<PaymentProvider, number> = {
  simulate: 300,
  mtn_momo: 250,
  airtel_money: 250,
  card: 350,
};

function parseOverrides(): Partial<Record<PaymentProvider, number>> {
  const raw = process.env.PROCESSING_FEE_BPS_JSON?.trim();
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as Record<string, number>;
    const out: Partial<Record<PaymentProvider, number>> = {};
    for (const key of Object.keys(DEFAULT_FEE_BPS) as PaymentProvider[]) {
      const n = Number(parsed[key]);
      if (Number.isFinite(n) && n >= 0 && n <= 10_000) out[key] = Math.floor(n);
    }
    return out;
  } catch {
    return {};
  }
}

export function processingFeeBpsFor(provider: PaymentProvider): number {
  const overrides = parseOverrides();
  return overrides[provider] ?? DEFAULT_FEE_BPS[provider] ?? 300;
}

export function listProcessingFeeSchedule(): Record<PaymentProvider, number> {
  const overrides = parseOverrides();
  return {
    simulate: overrides.simulate ?? DEFAULT_FEE_BPS.simulate,
    mtn_momo: overrides.mtn_momo ?? DEFAULT_FEE_BPS.mtn_momo,
    airtel_money: overrides.airtel_money ?? DEFAULT_FEE_BPS.airtel_money,
    card: overrides.card ?? DEFAULT_FEE_BPS.card,
  };
}
