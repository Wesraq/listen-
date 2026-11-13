import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

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

  constructor() {
    this.ensurePrototypeSession();
  }

  onModuleInit() {
    this.loadUsers();
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

  private loadUsers() {
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

  private persistUsers() {
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

  findAdminByEmail(email: string): AdminAccount | undefined {
    if (email.toLowerCase() === this.seedAdmin.email) return this.seedAdmin;
    return undefined;
  }

  createSession(admin: AdminAccount): AdminSession {
    // Seed admin always gets the stable prototype token (survives tsx restarts).
    if (admin.email.toLowerCase() === this.seedAdmin.email) {
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
    return item;
  }

  listAudit() {
    return [...this.audit].reverse();
  }

  record(actorEmail: string, action: string, target: string, reason?: string) {
    this.audit.push({
      id: randomUUID(),
      actorEmail,
      action,
      target,
      at: new Date().toISOString(),
      reason,
    });
  }
}
