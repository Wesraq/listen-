# Listen+ financial engine — configured state

Prototype double-entry ledger shared by purchases, subscriptions, advertising, and creator cashouts. Mobile is untrusted for entitlements and payouts; Cloud Run `listen-api` is source of truth when reachable.

**Live API:** `https://listen-api-851945155141.us-central1.run.app/v1`  
**Revision (as of this doc):** `listen-api-00012+`  
**Market / currency:** Zambia · ZMW (minor units = ngwee; 100 = ZMW 1.00)

---

## 1. Architecture

| Layer | Role |
| --- | --- |
| `LedgerService` / `LedgerStore` | Double-entry journals; creator payable balances; cashout holds |
| `PaymentsService` | Payment intents → webhook/confirm → `settleTitlePurchase` → library grant |
| `AdsService` | Campaigns + AdMob complete/SSV → `settleAdvertising` → Studio earning mirror |
| `ConsumptionService` | Qualified listen/read minutes → Studio sale + `settleStudioSale` |
| `StudioStore.sales` | Creator-facing statement lines + by-format totals |
| Admin Finance tab | Cashout queue + advertising settlement list |

Persistence: Firestore when `DATA_BACKEND=firestore` (collections under `FIRESTORE_PREFIX`, e.g. `listen` / `finance_journals`).

---

## 2. Chart of accounts (ledger)

**System accounts**

- `assets:processor_clearing`
- `assets:platform_cash`
- `liability:unallocated_receipts`
- `liability:subscription_deferred`
- `liability:creator_pool`
- `revenue:content_sales`
- `revenue:subscription`
- `revenue:advertising`
- `revenue:payout_fees`
- `expense:processing_fees`
- `expense:refunds`
- `expense:payout_fees`

**Per-creator:** `liability:creator_payable:{uid}`

**Journal kinds:** `payment_settlement` · `subscription_settlement` · `ad_settlement` · `creator_earning` · `payout` · `refund` · `adjustment`

Idempotency: `(referenceType, referenceId)` — e.g. `payment_intent` / intent id, `ad_completion` / client or SSV id, `studio_sale` / sale id, `cashout` / cashout id.

---

## 3. Commercial splits & fees

| Stream | Creator | Platform | Notes |
| --- | --- | --- | --- |
| Title purchase | **70%** of net | **30%** of net | Net = gross − **3%** processing fee (`processingFeeBps` 300) |
| Subscription pool | **60%** of pool credit | **40%** | Pool allocation from qualified minutes |
| Advertising | **55%** of gross ad credit | **45%** | Verified AdMob reward / SSV only |
| Format weights (sub pool UI) | ebook 30% · audiobook 45% · podcast 25% | — | Display / allocation policy in Studio |

**Cashout**

| Rule | Value |
| --- | --- |
| Hold window | **7 days** after payable credit |
| Minimum payout | **ZMW 50.00** (`5000` minor) |
| Payout fee | **ZMW 2.00** flat (creator-paid, retained as `revenue:payout_fees`) |
| Rails | `mtn_momo` · `airtel_money` · `bank` |

**Balances**

- **Earned** = credits to creator payable  
- **On hold** = credits younger than 7 days (+ in-flight cashout requests)  
- **Cashout available** = earned − paid out − hold − in-flight  
- Studio **by format** = sum of Studio sale lines (mirrors ledger for new settlements; history may include pre-ledger rows that are backfilled on `GET /studio/sales`)

---

## 4. Payments

**Providers (intent field):** `simulate` · `mtn_momo` · `airtel_money` · `card`  
**Mode:** `PAYMENTS_MODE=simulate` (sandbox adapters; MoMo/card UX paths exist, live keys not connected)

**Env (local `apps/api/.env` + Cloud Run)**

| Variable | Local | Cloud Run deploy |
| --- | --- | --- |
| `PAYMENTS_MODE` | `simulate` | `simulate` |
| `ALLOW_SIMULATED_PAYMENTS` | `true` | `true` |
| `ALLOW_CLIENT_GRANTS` | `false` | `true` (prototype) |
| `PAYMENT_WEBHOOK_SECRET` | set locally | from deploy env / default placeholder — set real secret before live webhooks |
| `AD_GROSS_MINOR` | `50` | `50` (override via shell when deploying) |

**Endpoints**

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/v1/payments/intents` | Create intent (title purchase or subscription) |
| `POST` | `/v1/payments/intents/:id/confirm` | Sandbox confirm when `ALLOW_SIMULATED_PAYMENTS=true` |
| `POST` | `/v1/payments/webhooks` | Provider webhook (HMAC / shared secret) |

On success: ledger `settleTitlePurchase` → Studio `recordEarning` (note includes `Ledger {journalId}`) → library grant with `skipEarning`.

---

## 5. Cashouts

**Creator**

| Method | Path |
| --- | --- |
| `GET` | `/v1/finance/me/balances` |
| `GET` | `/v1/finance/me/cashouts` |
| `POST` | `/v1/finance/me/cashouts` |

Studio Earnings → Request payout (blocked if available &lt; min).

**Admin**

| Method | Path |
| --- | --- |
| `GET` | `/v1/admin/payouts` |
| `POST` | `/v1/admin/payouts/:id/decision` | body `status`: `approved` · `rejected` · `settled` |

Statuses: `requested` → `approved` → `settled` (or `rejected` / `failed`). Settlement debits creator payable and credits clearing / payout fee revenue.

---

## 6. Advertising

**Campaign (seeded):** `network_default` — Listen+ / AdMob rewarded network  
**Gross per verified completion:** `AD_GROSS_MINOR` (default **50** = ZMW 0.50)  
**Hourly cap:** **3** completions per listener  
**Placements:** preroll · midroll · chapter (reader)

**Endpoints**

| Method | Path | Auth |
| --- | --- | --- |
| `GET` | `/v1/ads/campaigns` | public |
| `POST` | `/v1/ads/complete` | Bearer — requires `rewardEarned: true` for AdMob source |
| `GET`/`POST` | `/v1/ads/ssv` | AdMob SSV callback (configure in AdMob console) |

**SSV URL to set in AdMob:**  
`https://listen-api-851945155141.us-central1.run.app/v1/ads/ssv`  
Client `custom_data`: `titleId|placement|listenerUid`

Settlement: `settleAdvertising` (55/45) → Studio earning with `ledger` in note. Titles must be `free_with_ads` and have `creatorUid`.

**Mobile AdMob** (`apps/mobile/lib/config/ad_config.dart`)

- Default: **Google test** app/unit IDs (`ADMOB_USE_TEST_ADS` default `true`)
- Production via `--dart-define=ADMOB_*` + Info.plist / AndroidManifest app IDs
- Bundle / application: iOS `io.listen.listen` · Android `com.listenplus.listen_plus`
- Flow: rewarded interstitial → `POST /ads/complete` with `rewardEarned: true`

---

## 7. Studio earnings alignment

`GET /v1/studio/sales`:

1. Loads Studio sale lines for the creator  
2. **Backfills** lines not already on the ledger (skips notes containing `ledger`; idempotent `studio_sale` refs)  
3. Returns **cashout available / on hold** from `creatorBalance`  
4. Hero total = max(Studio creator-share sum, ledger earned)  
5. By-format cards from Studio lines (ebook / audiobook / podcast / advertising)

UI labels: “Creator share earned”, “Cashout available”, “On hold (Nd)”.

---

## 8. Admin ops console

`apps/admin-web` · seeded admin (`ADMIN_EMAIL` / `ADMIN_PASSWORD` in local `.env` only — not committed).

| Surface | Behaviour |
| --- | --- |
| Overview | Pending creators, moderation, payout queue, **ad settlements count**, **ad platform share** |
| Finance | Cashout approve / settle / reject + **Advertising settlements** table |
| `GET /v1/admin/ads` | Recent `ad_settlement` journals |

---

## 9. Auth, data, media (supporting)

| Variable | Configured |
| --- | --- |
| `AUTH_MODE` | local `firebase` · Cloud Run `hybrid` |
| `FIREBASE_PROJECT_ID` | `listenplus-d9188` |
| `DATA_BACKEND` | `firestore` |
| `MEDIA_BACKEND` | `firebase` |
| `FIRESTORE_PREFIX` | `listen` |
| `MEDIA_REQUIRE_SIGNED` | local `true` |
| Firebase iOS | configured (`io.listen.listen`) |
| Android `google-services.json` | not in repo until provided |

Mobile API base: release builds default to Cloud Run (`ApiConfig.publicDevHost`); override with `--dart-define=LISTEN_API_BASE=…`.

---

## 10. Git milestones (finance track)

| Commit | Summary |
| --- | --- |
| `e3caf67` | Financial ledger + multi-rail payment intents |
| `5db4846` | Sandbox payment confirms on Cloud Run |
| `83f43a4` | Creator cashouts through shared ledger |
| `348f4fa` | Ads settle on ledger + admin visibility |
| `8fd55a7` | Studio cashout balances aligned / backfill |

---

## 11. Not live yet (explicit)

- Real MTN MoMo / Airtel Money / card processor keys and production webhooks  
- Advertiser self-serve campaign UI (seed campaign only)  
- AdMob **production** app/unit IDs + SSV signature verification hardening  
- Direct AdMob → creator payout (AdMob pays publisher; creator split is internal ledger only)  
- Postgres as system of record (`DATABASE_URL` kept for local fallback only)  
- Refund / reversal journals end-to-end in product UI  

---

## 12. How to verify quickly

1. Purchase (simulate confirm) → Studio sale + ledger payable + library own  
2. Free-with-ads title → watch rewarded ad → Advertising format total ↑ · hold/available update  
3. Refresh Studio Earnings → backfill runs; cashout available reflects aged credits  
4. Request payout ≥ ZMW 50 available → admin Finance approve → settle  
5. `GET /v1/ads/campaigns` → `network_default` with `grossMinor: 50`
