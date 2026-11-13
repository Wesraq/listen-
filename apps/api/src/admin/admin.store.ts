import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { DbService } from '../db/db.service';
import { FirestoreService } from '../db/firestore.service';
import {
  AdminAccount,
  AdminSession,
  AdminUserRow,
  AuditEntry,
  ModerationItem,
  PayoutRequest,
} from './admin.types';

@Injectable()
export class AdminStore implements OnModuleInit {
  private readonly logger = new Logger(AdminStore.name);
  private readonly usersFile = join(process.cwd(), '.data', 'admin-users.json');
  private readonly ledgerFile = join(process.cwd(), '.data', 'admin-ledger.json');

  /** Local prototype admin — override with ADMIN_EMAIL / ADMIN_PASSWORD env. */
  readonly seedAdmin: AdminAccount = {
    id: 'admin-1',
    email: (process.env.ADMIN_EMAIL ?? 'admin@listen.plus').toLowerCase(),
    displayName: process.env.ADMIN_NAME ?? 'Listen+ Admin',
    role: 'admin',
    password: process.env.ADMIN_PASSWORD ?? 'ListenAdmin1!',
  };

  private readonly sessions = new Map<string, AdminSession>();

  /** Stable prototype token so admin-web survives API hot-reloads. */
  static readonly PROTOTYPE_TOKEN = 'admin.prototype';

  private readonly users: AdminUserRow[] = [];

  private readonly moderation: ModerationItem[] = [];

  private readonly payouts: PayoutRequest[] = [];

  private readonly audit: AuditEntry[] = [];

  constructor(
    @Inject(DbService) private readonly db: DbService,
    @Inject(FirestoreService) private readonly fs: FirestoreService,
  ) {
    if (this.allowPrototypeToken()) {
      this.ensurePrototypeSession();
    } else {
      this.logger.warn(
        'Admin prototype token disabled (Cloud Run / ADMIN_ALLOW_PROTOTYPE_TOKEN≠true). Use password login.',
      );
    }
  }

  private onCloud(): boolean {
    return Boolean(process.env.K_SERVICE || process.env.FORCE_CLOUD_SECURITY === 'true');
  }

  private allowPrototypeToken(): boolean {
    if ((process.env.ADMIN_ALLOW_PROTOTYPE_TOKEN ?? '').toLowerCase() === 'true') return true;
    if ((process.env.ADMIN_ALLOW_PROTOTYPE_TOKEN ?? '').toLowerCase() === 'false') return false;
    return !this.onCloud();
  }

  async onModuleInit() {
    if (this.fs.enabled) {
      await this.loadFromFirestore();
      if (this.users.length === 0) {
        this.loadUsersFromDisk();
        this.loadLedgerFromDisk();
        if (this.users.length > 0 || this.audit.length > 0) {
          await this.persistAllToFirestore();
          this.logger.log('Migrated admin profiles/ledger from disk → Firestore');
        }
      }
      return;
    }
    if (this.db.enabled) {
      await this.loadFromDb();
      if (this.users.length === 0) {
        this.loadUsersFromDisk();
        this.loadLedgerFromDisk();
        if (this.users.length > 0 || this.audit.length > 0) {
          await this.persistAllToDb();
          this.logger.log('Migrated admin profiles/ledger from disk → Postgres');
        }
      }
      return;
    }
    this.loadUsersFromDisk();
    this.loadLedgerFromDisk();
  }

  private ensurePrototypeSession() {
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
    this.sessions.set(AdminStore.PROTOTYPE_TOKEN, {
      token: AdminStore.PROTOTYPE_TOKEN,
      admin: {
        id: this.seedAdmin.id,
        email: this.seedAdmin.email,
        displayName: this.seedAdmin.displayName,
        role: this.seedAdmin.role,
      },
      expiresAt,
    });
  }

  private loadUsersFromDisk() {
    try {
      if (!existsSync(this.usersFile)) return;
      const raw = JSON.parse(readFileSync(this.usersFile, 'utf8')) as {
        users?: AdminUserRow[];
      };
      if (!Array.isArray(raw.users)) return;
      this.users.splice(0, this.users.length, ...raw.users);
      this.logger.log(`Loaded ${this.users.length} consumer profile(s) from disk`);
    } catch (error) {
      this.logger.warn(`Failed to load admin users: ${error}`);
    }
  }

  private loadLedgerFromDisk() {
    try {
      if (!existsSync(this.ledgerFile)) return;
      const raw = JSON.parse(readFileSync(this.ledgerFile, 'utf8')) as {
        moderation?: ModerationItem[];
        payouts?: PayoutRequest[];
        audit?: AuditEntry[];
      };
      if (Array.isArray(raw.moderation)) {
        this.moderation.splice(0, this.moderation.length, ...raw.moderation);
      }
      if (Array.isArray(raw.payouts)) {
        this.payouts.splice(0, this.payouts.length, ...raw.payouts);
      }
      if (Array.isArray(raw.audit)) {
        this.audit.splice(0, this.audit.length, ...raw.audit);
      }
    } catch (error) {
      this.logger.warn(`Failed to load admin ledger: ${error}`);
    }
  }

  private persistUsers() {
    void this.persistUsersAsync();
  }

  private async persistUsersAsync() {
    if (this.fs.enabled) {
      try {
        for (const user of this.users) {
          await this.fs.set('admin_users', user.uid, { payload: user });
        }
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist admin users to Firestore: ${error}`);
      }
    }
    if (this.db.enabled) {
      try {
        for (const user of this.users) {
          await this.db.query(
            `INSERT INTO admin_users
               (uid, email, display_name, market, role, creator_status, created_at, payload)
             VALUES ($1, $2, $3, $4, $5, $6, $7::timestamptz, $8::jsonb)
             ON CONFLICT (uid) DO UPDATE SET
               email = EXCLUDED.email,
               display_name = EXCLUDED.display_name,
               market = EXCLUDED.market,
               role = EXCLUDED.role,
               creator_status = EXCLUDED.creator_status,
               payload = EXCLUDED.payload`,
            [
              user.uid,
              user.email,
              user.displayName,
              user.market,
              user.role,
              user.creatorStatus,
              user.createdAt,
              JSON.stringify(user),
            ],
          );
        }
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist admin users to Postgres: ${error}`);
      }
    }
    try {
      mkdirSync(dirname(this.usersFile), { recursive: true });
      writeFileSync(
        this.usersFile,
        JSON.stringify({ users: this.users }, null, 2),
        'utf8',
      );
    } catch (error) {
      this.logger.warn(`Failed to persist admin users: ${error}`);
    }
  }

  private persistLedger() {
    void this.persistLedgerAsync();
  }

  private async persistLedgerAsync() {
    if (this.fs.enabled) {
      try {
        for (const item of this.moderation) {
          await this.fs.set('admin_moderation', item.id, { payload: item, status: item.status });
        }
        for (const item of this.payouts) {
          await this.fs.set('admin_payouts', item.id, { payload: item, status: item.status });
        }
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist admin ledger to Firestore: ${error}`);
      }
    }
    if (this.db.enabled) {
      try {
        for (const item of this.moderation) {
          await this.db.query(
            `INSERT INTO admin_moderation (id, payload, status, updated_at)
             VALUES ($1, $2::jsonb, $3, NOW())
             ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, status = EXCLUDED.status, updated_at = NOW()`,
            [item.id, JSON.stringify(item), item.status],
          );
        }
        for (const item of this.payouts) {
          await this.db.query(
            `INSERT INTO admin_payouts (id, payload, status, updated_at)
             VALUES ($1, $2::jsonb, $3, NOW())
             ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, status = EXCLUDED.status, updated_at = NOW()`,
            [item.id, JSON.stringify(item), item.status],
          );
        }
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist admin ledger to Postgres: ${error}`);
      }
    }
    try {
      mkdirSync(dirname(this.ledgerFile), { recursive: true });
      writeFileSync(
        this.ledgerFile,
        JSON.stringify(
          {
            moderation: this.moderation,
            payouts: this.payouts,
            audit: this.audit,
          },
          null,
          2,
        ),
        'utf8',
      );
    } catch (error) {
      this.logger.warn(`Failed to persist admin ledger: ${error}`);
    }
  }

  private async loadFromFirestore() {
    try {
      const users = await this.fs.list<{ payload: AdminUserRow }>('admin_users');
      this.users.splice(
        0,
        this.users.length,
        ...users.map((row) => row.payload).filter(Boolean),
      );

      const moderation = await this.fs.list<{ payload: ModerationItem }>('admin_moderation');
      this.moderation.splice(
        0,
        this.moderation.length,
        ...moderation.map((row) => row.payload).filter(Boolean),
      );

      const payouts = await this.fs.list<{ payload: PayoutRequest }>('admin_payouts');
      this.payouts.splice(
        0,
        this.payouts.length,
        ...payouts.map((row) => row.payload).filter(Boolean),
      );

      const audit = await this.fs.list<{ payload: AuditEntry }>('admin_audit');
      this.audit.splice(
        0,
        this.audit.length,
        ...audit
          .map((row) => row.payload)
          .filter(Boolean)
          .sort((a, b) => (a.at < b.at ? -1 : 1)),
      );

      this.logger.log(
        `Loaded ${this.users.length} profile(s), ${this.moderation.length} moderation, ${this.audit.length} audit from Firestore`,
      );
    } catch (error) {
      this.logger.warn(`Failed to load admin store from Firestore: ${error}`);
    }
  }

  private async loadFromDb() {
    try {
      const users = await this.db.query<{ payload: AdminUserRow }>(
        'SELECT payload FROM admin_users',
      );
      this.users.splice(
        0,
        this.users.length,
        ...users.rows.map((row) => row.payload).filter(Boolean),
      );

      const moderation = await this.db.query<{ payload: ModerationItem }>(
        'SELECT payload FROM admin_moderation',
      );
      this.moderation.splice(
        0,
        this.moderation.length,
        ...moderation.rows.map((row) => row.payload).filter(Boolean),
      );

      const payouts = await this.db.query<{ payload: PayoutRequest }>(
        'SELECT payload FROM admin_payouts',
      );
      this.payouts.splice(
        0,
        this.payouts.length,
        ...payouts.rows.map((row) => row.payload).filter(Boolean),
      );

      const audit = await this.db.query<{ payload: AuditEntry }>(
        'SELECT payload FROM admin_audit ORDER BY at ASC',
      );
      this.audit.splice(
        0,
        this.audit.length,
        ...audit.rows.map((row) => row.payload).filter(Boolean),
      );

      this.logger.log(
        `Loaded ${this.users.length} profile(s), ${this.moderation.length} moderation, ${this.audit.length} audit from Postgres`,
      );
    } catch (error) {
      this.logger.warn(`Failed to load admin store from Postgres: ${error}`);
    }
  }

  private async persistAllToFirestore() {
    await this.persistUsersAsync();
    await this.persistLedgerAsync();
    for (const entry of this.audit) {
      await this.persistAuditRow(entry);
    }
  }

  private async persistAllToDb() {
    await this.persistUsersAsync();
    await this.persistLedgerAsync();
    for (const entry of this.audit) {
      await this.persistAuditRow(entry);
    }
  }

  private async persistAuditRow(entry: AuditEntry) {
    if (this.fs.enabled) {
      try {
        await this.fs.set('admin_audit', entry.id, { payload: entry });
      } catch (error) {
        this.logger.warn(`Failed to persist audit row to Firestore: ${error}`);
      }
      return;
    }
    if (!this.db.enabled) return;
    try {
      await this.db.query(
        `INSERT INTO admin_audit (id, actor_email, action, target, at, reason, payload)
         VALUES ($1, $2, $3, $4, $5::timestamptz, $6, $7::jsonb)
         ON CONFLICT (id) DO NOTHING`,
        [
          entry.id,
          entry.actorEmail,
          entry.action,
          entry.target,
          entry.at,
          entry.reason ?? null,
          JSON.stringify(entry),
        ],
      );
    } catch (error) {
      this.logger.warn(`Failed to persist audit row: ${error}`);
    }
  }

  findAdminByEmail(email: string): AdminAccount | undefined {
    if (email.toLowerCase() === this.seedAdmin.email) return this.seedAdmin;
    return undefined;
  }

  createSession(admin: AdminAccount): AdminSession {
    // Local only: seed admin may use the stable prototype token (survives tsx restarts).
    if (admin.email.toLowerCase() === this.seedAdmin.email && this.allowPrototypeToken()) {
      this.ensurePrototypeSession();
      const session = this.sessions.get(AdminStore.PROTOTYPE_TOKEN)!;
      this.record(admin.email, 'admin_login', admin.id);
      return session;
    }

    const token = `admin.${randomUUID()}`;
    const session: AdminSession = {
      token,
      admin: {
        id: admin.id,
        email: admin.email,
        displayName: admin.displayName,
        role: admin.role,
      },
      expiresAt: new Date(Date.now() + 12 * 60 * 60 * 1000).toISOString(),
    };
    this.sessions.set(token, session);
    this.record(admin.email, 'admin_login', admin.id);
    return session;
  }

  resolveSession(token?: string): AdminSession | undefined {
    if (!token) return undefined;
    if (token === AdminStore.PROTOTYPE_TOKEN) {
      if (!this.allowPrototypeToken()) return undefined;
      this.ensurePrototypeSession();
    }
    const session = this.sessions.get(token);
    if (!session) return undefined;
    if (new Date(session.expiresAt).getTime() < Date.now()) {
      this.sessions.delete(token);
      if (token === AdminStore.PROTOTYPE_TOKEN) {
        this.ensurePrototypeSession();
        return this.sessions.get(AdminStore.PROTOTYPE_TOKEN);
      }
      return undefined;
    }
    return session;
  }

  overview() {
    return {
      pendingCreators: this.users.filter((u) => u.creatorStatus === 'pending').length,
      moderationQueue: this.moderation.filter((m) => m.status === 'submitted' || m.status === 'in_review')
        .length,
      payoutQueue: this.payouts.filter((p) => p.status === 'requested').length,
      paymentExceptions: 0,
      users: this.users.length,
      market: { code: 'ZM', currency: 'ZMW' },
    };
  }

  listUsers() {
    return this.users;
  }

  findUser(uid?: string, email?: string): AdminUserRow | undefined {
    // Prefer email so admin approvals on seed/demo rows bind to the live Firebase uid.
    if (email) {
      const normalized = email.toLowerCase();
      const byEmail = this.users.find((item) => item.email.toLowerCase() === normalized);
      if (byEmail) return byEmail;
    }
    if (uid) {
      return this.users.find((item) => item.uid === uid);
    }
    return undefined;
  }

  /**
   * Ensure a consumer profile exists and is linked to the current Firebase uid.
   * Rebinds seed/demo rows matched by email so admin approvals follow the real account.
   */
  ensureConsumer(input: {
    uid: string;
    email?: string;
    displayName?: string;
  }): AdminUserRow {
    const email = input.email?.trim().toLowerCase();
    const byEmail = email
      ? this.users.find((item) => item.email.toLowerCase() === email)
      : undefined;
    const byUid = this.users.find((item) => item.uid === input.uid);

    let user = byEmail ?? byUid;
    let dirty = false;
    if (!user) {
      user = {
        uid: input.uid,
        email: email || `${input.uid}@listeners.listen.plus`,
        displayName: input.displayName?.trim() || 'Listener',
        market: 'ZM',
        role: 'listener',
        creatorStatus: 'none',
        createdAt: new Date().toISOString(),
      };
      this.users.push(user);
      this.persistUsers();
      return user;
    }

    // Merge a uid-only duplicate into the email-matched (often already approved) row.
    if (byEmail && byUid && byEmail !== byUid) {
      const rank = (status: AdminUserRow['creatorStatus']) =>
        ({ approved: 3, pending: 2, rejected: 1, none: 0 })[status];
      if (rank(byUid.creatorStatus) > rank(byEmail.creatorStatus)) {
        byEmail.creatorStatus = byUid.creatorStatus;
        byEmail.role = byUid.role;
      }
      this.users.splice(this.users.indexOf(byUid), 1);
      this.record('system', 'profile_merge', `${byUid.uid}->${byEmail.uid}`, email);
      user = byEmail;
      dirty = true;
    }

    if (user.uid !== input.uid) {
      this.record('system', 'uid_rebind', `${user.uid}->${input.uid}`, email);
      user.uid = input.uid;
      dirty = true;
    }
    if (email && user.email !== email) {
      user.email = email;
      dirty = true;
    }
    if (input.displayName?.trim() && user.displayName !== input.displayName.trim()) {
      user.displayName = input.displayName.trim();
      dirty = true;
    }
    if (dirty) this.persistUsers();
    return user;
  }

  applyCreator(input: {
    uid: string;
    email?: string;
    displayName?: string;
  }): AdminUserRow {
    const user = this.ensureConsumer(input);
    user.role = 'creator';
    if (user.creatorStatus !== 'approved') {
      user.creatorStatus = 'pending';
    }
    this.record(user.email, 'creator_apply', user.uid, 'Mobile Studio application');
    this.persistUsers();
    return user;
  }

  setCreatorStatus(
    uid: string,
    status: AdminUserRow['creatorStatus'],
    actorEmail: string,
    reason?: string,
  ) {
    const user =
      this.users.find((item) => item.uid === uid) ??
      this.users.find((item) => item.email.toLowerCase() === uid.toLowerCase());
    if (!user) return null;
    user.creatorStatus = status;
    if (status === 'approved' || status === 'pending') {
      user.role = 'creator';
    }
    this.record(actorEmail, `creator_${status}`, user.uid, reason);
    this.persistUsers();
    return user;
  }

  listModeration() {
    return this.moderation;
  }

  enqueueModeration(item: ModerationItem) {
    const existing = this.moderation.findIndex((row) => row.id === item.id);
    if (existing >= 0) this.moderation[existing] = item;
    else this.moderation.push(item);
    this.persistLedger();
    return item;
  }

  moderate(
    id: string,
    status: ModerationItem['status'],
    actorEmail: string,
    notes?: string,
  ) {
    const item = this.moderation.find((row) => row.id === id);
    if (!item) return null;
    item.status = status;
    item.notes = notes;
    this.record(actorEmail, `content_${status}`, id, notes);
    this.persistLedger();
    return item;
  }

  listPayouts() {
    return this.payouts;
  }

  decidePayout(
    id: string,
    status: Extract<PayoutRequest['status'], 'approved' | 'rejected' | 'settled'>,
    actorEmail: string,
    reference?: string,
  ) {
    const item = this.payouts.find((row) => row.id === id);
    if (!item) return null;
    item.status = status;
    if (reference) item.reference = reference;
    this.record(actorEmail, `payout_${status}`, id, reference);
    this.persistLedger();
    return item;
  }

  listAudit() {
    return [...this.audit].reverse();
  }

  record(actorEmail: string, action: string, target: string, reason?: string) {
    const entry: AuditEntry = {
      id: randomUUID(),
      actorEmail,
      action,
      target,
      at: new Date().toISOString(),
      reason,
    };
    this.audit.push(entry);
    void this.persistAuditRow(entry);
    if (!this.db.enabled && !this.fs.enabled) this.persistLedger();
  }
}
