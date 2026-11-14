# Listen+ financial engine — configured state

Prototype double-entry ledger shared by purchases, subscriptions, advertising, and creator cashouts. Mobile is untrusted for entitlements and payouts; Cloud Run `listen-api` is source of truth when reachable.

**Live API:** `https://listen-api-851945155141.us-central1.run.app/v1`  
**Market / currency:** Zambia · ZMW (minor units = ngwee; 100 = ZMW 1.00)

---

## Integrity rules (release blockers addressed)

| Rule | Enforcement |
| --- | --- |
| Mobile cannot grant paid entitlements | `ALLOW_CLIENT_GRANTS=false` (local + Cloud Run) |
| Client `rewardEarned` never pays creators | `POST /ads/complete` is telemetry/UX only (`credited: false`) |
| AdMob SSV must verify | ECDSA SHA-256 vs Google verifier keys; fresh timestamp; unique `transaction_id` |
| Fixed `AD_GROSS_MINOR` is not Google revenue | Labelled **SIMULATED**; journals `cashoutEligible: false` |
| Cashoutable ads only from reconciliation | `POST /admin/ads/reconcile` with reported gross |
| Processing fees by provider | `processingFeeBpsFor(provider)` + optional `PROCESSING_FEE_BPS_JSON` |
| Cashout ≠ admin click | Statuses include `processing` / `provider_confirmed`; ledger settle only after confirm |
| GET must not mutate ledger | `GET /studio/sales` is read-only; migration is `POST /admin/finance/migrate-studio-sales` |

---

## 1. Architecture

| Layer | Role |
| --- | --- |
| `LedgerService` / `LedgerStore` | Double-entry journals; cashoutable creator balances; cashout lifecycle |
| `PaymentsService` | Payment intents → webhook/confirm → `settleTitlePurchase` → library grant |
| `AdsService` | Campaigns; client complete (non-paying); SSV verify; admin reconcile |
| `ConsumptionService` | Qualified minutes → Studio estimate (+ non-cashoutable journal optional) |
| `StudioStore.sales` | Creator-facing statement / by-format (may include simulated lines) |
| Admin Finance | Cashout lifecycle + ad settlements + fee schedule + migrations |

Persistence: Firestore when `DATA_BACKEND=firestore`.

---

## 2. Chart of accounts

System accounts include processor clearing, content/subscription/advertising revenue, processing and payout fee expense/revenue, creator pool, etc.

**Per-creator:** `liability:creator_payable:{uid}`

**Journal metadata**

- `cashoutEligible` — when `false`, excluded from cashout available/earned
- `settlementSource` — e.g. `payment` · `ssv_simulated` · `ad_reconciled` · `studio_migration`

**Idempotency:** `(referenceType, referenceId)`

---

## 3. Commercial splits & fees

| Stream | Creator | Platform | Cashoutable? |
| --- | --- | --- | --- |
| Title purchase | 70% of net | 30% of net | Yes (after verified payment) |
| Subscription pool estimates | 60% | 40% | No until reconciled funding |
| Advertising (SSV simulate) | 55% of **simulated** gross | 45% | **No** |
| Advertising (admin reconcile) | 55% of **reported** gross | 45% | Yes |

**Provider processing fees (bps of gross, before royalty split)**

| Provider | Default bps | Notes |
| --- | --- | --- |
| `simulate` | 300 (3%) | Sandbox |
| `mtn_momo` | 250 | Provisional — replace with contracted rate |
| `airtel_money` | 250 | Provisional |
| `card` | 350 | Provisional |

Override: `PROCESSING_FEE_BPS_JSON={"simulate":300,"mtn_momo":250,...}`  
Reconcile against provider settlement statements before production.

**Cashout**

| Rule | Value |
| --- | --- |
| Hold | 7 days on cashoutable credits |
| Minimum | ZMW 50.00 |
| Fee | ZMW 2.00 flat |
| Rails | `mtn_momo` · `airtel_money` · `bank` |

**Lifecycle**

`requested` → `approved` → `processing` → `provider_confirmed` → `settled`  
Also: `failed` · `rejected` · `reversed` (reversal journaling not automated yet)

- **approved** = finance OK to disburse (no money moved)  
- **processing** = instruction recorded for rail adapter (live MoMo/bank send not wired)  
- **provider_confirmed** = requires `providerRef` from rail/webhook/statement  
- **settled** = ledger debit of creator payable — **only** from `provider_confirmed`

---

## 4. Payments

**Env**

| Variable | Local | Cloud Run |
| --- | --- | --- |
| `PAYMENTS_MODE` | `simulate` | `simulate` |
| `ALLOW_SIMULATED_PAYMENTS` | `true` | `true` |
| `ALLOW_CLIENT_GRANTS` | **`false`** | **`false`** |
| `PAYMENT_WEBHOOK_SECRET` | set locally | set on deploy |

**Endpoints:** `POST /v1/payments/intents` · `…/confirm` · `…/webhooks`

---

## 5. Advertising

| Variable | Meaning |
| --- | --- |
| `AD_GROSS_MINOR` | Simulated ZMW minor per SSV (default 50) — **not** AdMob revenue |
| `ADS_SETTLEMENT_MODE` | `simulate` (default) · `off` · `reconciled` |

**Client** `POST /v1/ads/complete` — never creates payables (`rewardEarned` ignored for money).

**SSV** `GET/POST /v1/ads/ssv`

1. Verify signature against `https://www.gstatic.com/admob/reward/verifier-keys.json`
2. Reject stale `timestamp` (>10 minutes)
3. Reject replayed `transaction_id` (memory + ledger idempotency)
4. If `simulate`: post **non-cashoutable** illustrative journal  
5. If `reconciled` / `off`: verify only; no fixed-gross payable

**Cashoutable ads:** `POST /v1/admin/ads/reconcile` with `reportedGrossMinor` from network reporting.

**SSV URL:** `https://listen-api-851945155141.us-central1.run.app/v1/ads/ssv`

Mobile AdMob defaults remain Google **test** IDs until production dart-defines.

---

## 6. Studio earnings (read-only)

`GET /v1/studio/sales`:

- Returns Studio statement lines + by-format (may include simulated advertising)
- Overlays **cashout available / on hold / paid out** from cashoutable ledger only
- **Does not** create journals

**Migration (admin only):** `POST /v1/admin/finance/migrate-studio-sales`  
`{ "creatorUid": "…", "cashoutEligible": false }`  
Default non-cashoutable; set `cashoutEligible: true` only after finance sign-off that funds exist.

---

## 7. Admin

| Path | Purpose |
| --- | --- |
| `GET /admin/payouts` | Queue + lifecycle note |
| `POST /admin/payouts/:id/decision` | `approved` · `processing` · `provider_confirmed` · `settled` · `rejected` · `failed` |
| `GET /admin/ads` | Settlements + campaign mode + fee schedule |
| `POST /admin/ads/reconcile` | Cashoutable ad attribution from reported gross |
| `POST /admin/finance/migrate-studio-sales` | Controlled Studio→ledger migration |
| `GET /admin/finance/fee-schedule` | Provider fee bps |

---

## 8. Not live yet

- Real MTN MoMo / Airtel / card disbursement APIs (processing status is adapter-ready, not live send)
- AdMob production app/unit IDs
- Automated pull of AdMob mediation reports into reconcile
- Cashout `reversed` automated journals
- Postgres as system of record

---

## 9. Verify quickly

1. `POST /library/owned/:id` with Bearer → **403** (client grants off)  
2. `POST /ads/complete` with `rewardEarned: true` → `credited: false`, no cashout bump  
3. SSV without valid signature → **401**  
4. SSV simulate → Studio advertising may rise; **cashout available** unchanged  
5. Admin reconcile with reported gross → cashoutable earned increases (after hold)  
6. Cashout: cannot `settled` until `provider_confirmed` + `providerRef`
