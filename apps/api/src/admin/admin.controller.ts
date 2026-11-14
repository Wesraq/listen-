import {
  Body,
  Controller,
  Get,
  Inject,
  NotFoundException,
  Param,
  Post,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import { LedgerService } from '../finance/ledger.service';
import { LibraryStore } from '../library/library.store';
import { StudioStore } from '../studio/studio.store';
import { AdminGuard, ADMIN_SESSION_KEY } from './admin.guard';
import { AdminStore } from './admin.store';
import { AdminSession, ModerationItem, PayoutRequest } from './admin.types';

@Controller('admin')
export class AdminController {
  constructor(
    @Inject(AdminStore) private readonly store: AdminStore,
    @Inject(StudioStore) private readonly studio: StudioStore,
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(LibraryStore) private readonly library: LibraryStore,
    @Inject(LedgerService) private readonly ledger: LedgerService,
  ) {}

  @Post('auth/login')
  login(@Body() body: { email?: string; password?: string }) {
    const email = body.email?.trim().toLowerCase() ?? '';
    const password = body.password ?? '';
    const admin = this.store.findAdminByEmail(email);
    if (!admin || admin.password !== password) {
      throw new UnauthorizedException('Invalid admin email or password');
    }
    return this.store.createSession(admin);
  }

  @Get('me')
  @UseGuards(AdminGuard)
  me(@Req() req: Record<string, unknown>) {
    const session = req[ADMIN_SESSION_KEY] as AdminSession;
    return session.admin;
  }

  @Get('overview')
  @UseGuards(AdminGuard)
  overview() {
    return this.store.overview();
  }

  @Get('users')
  @UseGuards(AdminGuard)
  users() {
    return {
      items: this.store
        .listUsers()
        .map((user) => this.userSummary(user.uid, user.email))
        .filter((item): item is NonNullable<typeof item> => item != null),
    };
  }

  @Get('users/:uid')
  @UseGuards(AdminGuard)
  userProfile(@Param('uid') uid: string) {
    const profile = this.buildUserProfile(uid);
    if (!profile) throw new NotFoundException('User not found');
    return profile;
  }

  @Post('users/:uid/creator-status')
  @UseGuards(AdminGuard)
  setCreatorStatus(
    @Param('uid') uid: string,
    @Body() body: { status: 'pending' | 'approved' | 'rejected'; reason?: string },
    @Req() req: Record<string, unknown>,
  ) {
    const session = req[ADMIN_SESSION_KEY] as AdminSession;
    const updated = this.store.setCreatorStatus(uid, body.status, session.admin.email, body.reason);
    if (!updated) throw new NotFoundException('User not found');
    return this.buildUserProfile(updated.uid) ?? updated;
  }

  private userSummary(uid: string, email?: string) {
    const user = this.store.findUser(uid, email);
    if (!user) return null;
    const drafts = this.studio.listDrafts(user.uid, user.email);
    const owned = this.library.getOwned(user.uid);
    const saved = this.library.getSaved(user.uid);
    const sales = this.studio.salesFor(user.uid, user.email);
    return {
      ...user,
      draftsCount: drafts.length,
      submittedCount: drafts.filter((d) => d.status === 'submitted').length,
      liveCount: drafts.filter((d) => d.status === 'live').length,
      ownedCount: owned.length,
      savedCount: saved.length,
      grossSalesMinor: sales.grossSalesMinor,
      salesCurrency: sales.currency,
    };
  }

  private buildUserProfile(uidOrEmail: string) {
    const user =
      this.store.findUser(uidOrEmail) ??
      this.store.findUser(undefined, uidOrEmail) ??
      this.store.listUsers().find(
        (row) => row.uid === uidOrEmail || row.email.toLowerCase() === uidOrEmail.toLowerCase(),
      );
    if (!user) return null;

    const drafts = this.studio.listDrafts(user.uid, user.email);
    const ownedIds = this.library.getOwned(user.uid);
    const savedIds = this.library.getSaved(user.uid);
    const sales = this.studio.salesFor(user.uid, user.email);
    const content = this.moderationQueue().filter(
      (item) => item.creatorUid === user.uid || item.creatorName === user.email,
    );

    return {
      profile: {
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        market: user.market,
        role: user.role,
        creatorStatus: user.creatorStatus,
        createdAt: user.createdAt,
      },
      library: {
        ownedIds,
        savedIds,
        ownedCount: ownedIds.length,
        savedCount: savedIds.length,
      },
      studio: {
        drafts: drafts.map((draft) => ({
          id: draft.id,
          title: draft.title,
          format: draft.format,
          status: draft.status,
          prices: draft.prices,
          priceLabel: draft.prices
            .map((p) => `${p.currency} ${(p.amountMinor / 100).toFixed(2)}`)
            .join(' · '),
          mediaName: draft.mediaName,
          mediaKind: draft.mediaKind,
          mediaBytes: draft.mediaBytes,
          publishedTitleId: draft.publishedTitleId,
          createdAt: draft.createdAt,
          updatedAt: draft.updatedAt,
        })),
        draftsCount: drafts.length,
        submittedCount: drafts.filter((d) => d.status === 'submitted').length,
        liveCount: drafts.filter((d) => d.status === 'live').length,
      },
      sales: {
        currency: sales.currency,
        grossSalesMinor: sales.grossSalesMinor,
        availableMinor: sales.availableMinor,
        pendingMinor: sales.pendingMinor,
        recent: sales.sales.slice(0, 8),
      },
      moderation: content,
    };
  }

  @Get('moderation')
  @UseGuards(AdminGuard)
  moderation() {
    return { items: this.moderationQueue() };
  }

  @Post('moderation/:id/decision')
  @UseGuards(AdminGuard)
  moderate(
    @Param('id') id: string,
    @Body()
    body: {
      status: 'in_review' | 'changes_requested' | 'approved' | 'rejected';
      notes?: string;
    },
    @Req() req: Record<string, unknown>,
  ) {
    const session = req[ADMIN_SESSION_KEY] as AdminSession;
    const queue = this.moderationQueue();
    const current = queue.find((item) => item.id === id);
    if (!current) throw new NotFoundException('Moderation item not found');

    // Seed demo rows stay in AdminStore; Studio drafts are decided here.
    let updated =
      this.store.moderate(id, body.status, session.admin.email, body.notes) ??
      ({ ...current, status: body.status, notes: body.notes } satisfies ModerationItem);

    if (body.status === 'approved') {
      const draftId = updated.draftId ?? (id.startsWith('draft-') ? id : undefined);
      const draft = draftId ? this.studio.findDraft(draftId) : undefined;
      if (draft) {
        const zmw = draft.prices.find((p) => p.currency === 'ZMW') ?? draft.prices[0];
        const author =
          draft.creatorDisplayName?.trim() ||
          this.store.findUser(draft.creatorUid, draft.creatorEmail)?.displayName ||
          draft.creatorEmail;
        const published = this.catalogue.publishCreatorTitle({
          draftId: draft.id,
          title: draft.title,
          author,
          format: draft.format,
          priceMinor: zmw?.amountMinor ?? 0,
          currency: zmw?.currency ?? 'ZMW',
          prices: draft.prices,
          category: draft.genre,
          mediaName: draft.mediaName,
          mediaId: draft.mediaId,
          coverImageId: draft.coverImageId,
          monetisationMode: draft.monetisationMode,
          subscriptionEligible: draft.subscriptionEligible,
          creatorUid: draft.creatorUid,
          chapters: draft.chapters,
          episodes: draft.episodes,
        });
        this.studio.markLive(draft.id, published.id);
        // Prefer the live profile uid (email match) so Firebase accounts get the entitlement.
        const profile = this.store.findUser(draft.creatorUid, draft.creatorEmail);
        const ownerUid = profile?.uid ?? draft.creatorUid;
        this.store.setCreatorStatus(
          ownerUid,
          'approved',
          session.admin.email,
          `Auto-approved on content publish (${published.id})`,
        );
        if (ownerUid !== draft.creatorUid) {
          this.store.setCreatorStatus(
            draft.creatorUid,
            'approved',
            session.admin.email,
            `Auto-approved on content publish (${published.id})`,
          );
        }
        this.library.grantOwnership(ownerUid, published.id);
        if (ownerUid !== draft.creatorUid) {
          this.library.grantOwnership(draft.creatorUid, published.id);
          this.studio.updateDraft(draft.id, ownerUid, {
            creatorEmail: draft.creatorEmail,
            creatorDisplayName: draft.creatorDisplayName,
          });
        }
        updated = {
          ...updated,
          status: 'approved',
          draftId: draft.id,
          creatorUid: draft.creatorUid,
          publishedTitleId: published.id,
          priceLabel: this.priceLabel(draft.prices),
          mediaName: draft.mediaName,
          notes: body.notes ?? `Published “${published.name}” @ ${this.priceLabel(draft.prices)}`,
        };
        this.store.record(session.admin.email, 'content_published', published.id, draft.id);
      } else {
        this.store.record(session.admin.email, `content_${body.status}`, id, body.notes);
      }
    } else if (updated.draftId || id.startsWith('draft-')) {
      const draft = this.studio.findDraft(updated.draftId ?? id);
      if (draft && body.status === 'rejected') {
        if (draft.publishedTitleId) this.catalogue.removeTitle(draft.publishedTitleId);
        this.studio.updateDraft(draft.id, draft.creatorUid, { status: 'draft' });
      }
      this.store.record(session.admin.email, `content_${body.status}`, id, body.notes);
    }

    return updated;
  }

  private priceLabel(prices: { currency: string; amountMinor: number }[]): string {
    if (!prices.length) return 'No price';
    return prices.map((p) => `${p.currency} ${(p.amountMinor / 100).toFixed(2)}`).join(' · ');
  }

  private moderationQueue(): ModerationItem[] {
    const seeded = this.store.listModeration();
    const fromStudio: ModerationItem[] = this.studio.listSubmitted().map((draft) => ({
      id: draft.id,
      draftId: draft.id,
      title: draft.title,
      creatorName: draft.creatorDisplayName || draft.creatorEmail,
      format: draft.format,
      status: draft.status === 'live' ? 'approved' : 'submitted',
      submittedAt: draft.updatedAt || draft.createdAt,
      creatorUid: draft.creatorUid,
      publishedTitleId: draft.publishedTitleId,
      priceLabel: this.priceLabel(draft.prices),
      mediaName: draft.mediaName,
      notes:
        draft.status === 'live'
          ? `Live as ${draft.publishedTitleId}`
          : 'Awaiting rights & quality review',
    }));
    const seededIds = new Set(seeded.map((item) => item.id));
    return [...fromStudio.filter((item) => !seededIds.has(item.id)), ...seeded];
  }

  @Get('payouts')
  @UseGuards(AdminGuard)
  payouts() {
    const seeded = this.store.listPayouts();
    const fromLedger: PayoutRequest[] = this.ledger.listAllCashouts().map((c) => ({
      id: c.id,
      creatorName: c.creatorName,
      amountMinor: c.amountMinor,
      currency: c.currency,
      status: c.status === 'failed' ? 'rejected' : c.status,
      requestedAt: c.requestedAt,
      reference: c.providerRef || `${c.rail}:${c.destination}`,
    }));
    const seededIds = new Set(seeded.map((p) => p.id));
    return {
      items: [...fromLedger.filter((p) => !seededIds.has(p.id)), ...seeded],
    };
  }

  @Post('payouts/:id/decision')
  @UseGuards(AdminGuard)
  decidePayout(
    @Param('id') id: string,
    @Body()
    body: {
      status: 'approved' | 'rejected' | 'settled';
      reference?: string;
    },
    @Req() req: Record<string, unknown>,
  ) {
    const session = req[ADMIN_SESSION_KEY] as AdminSession;
    const cashout = this.ledger.getCashout(id);
    if (cashout) {
      const updated = this.ledger.decideCashout({
        id,
        status: body.status,
        actorEmail: session.admin.email,
        providerRef: body.reference,
        failureReason: body.status === 'rejected' ? body.reference : undefined,
      });
      this.store.record(session.admin.email, `payout_${body.status}`, id, body.reference);
      return {
        id: updated.id,
        creatorName: updated.creatorName,
        amountMinor: updated.amountMinor,
        currency: updated.currency,
        status: updated.status === 'failed' ? 'rejected' : updated.status,
        requestedAt: updated.requestedAt,
        reference: updated.providerRef || `${updated.rail}:${updated.destination}`,
        journalId: updated.journalId,
        netMinor: updated.netMinor,
        feeMinor: updated.feeMinor,
      };
    }
    const updated = this.store.decidePayout(id, body.status, session.admin.email, body.reference);
    if (!updated) throw new NotFoundException('Payout request not found');
    return updated;
  }

  @Get('audit')
  @UseGuards(AdminGuard)
  audit() {
    return { items: this.store.listAudit() };
  }
}
