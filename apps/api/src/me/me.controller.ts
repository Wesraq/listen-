import { Body, Controller, Get, Inject, Post, UseGuards } from '@nestjs/common';

import { AdminStore } from '../admin/admin.store';
import { AuthGuard } from '../auth/auth.guard';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { LibraryStore } from '../library/library.store';
import { StudioStore } from '../studio/studio.store';

@Controller('me')
@UseGuards(AuthGuard)
export class MeController {
  constructor(
    @Inject(AdminStore) private readonly profiles: AdminStore,
    @Inject(LibraryStore) private readonly library: LibraryStore,
    @Inject(StudioStore) private readonly studio: StudioStore,
    @Inject(AuthService) private readonly auth: AuthService,
  ) {}

  private firebaseVerifiedIdentity(): boolean {
    return this.auth.isFirebaseMode();
  }

  @Get()
  me(@CurrentUser() user: AuthUser) {
    // Email-based rebind is only safe with verified Firebase tokens (AUTH_MODE=firebase
    // on Cloud Run). Never rebind from spoofable hybrid/dev email claims.
    const verifiedEmail = Boolean(user.email) && this.firebaseVerifiedIdentity();
    const existing = this.profiles.findUser(
      user.uid,
      verifiedEmail ? user.email : undefined,
    );
    const previousUid = existing?.uid;
    const profile = this.profiles.ensureConsumer({
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
    });
    if (verifiedEmail && previousUid && previousUid !== profile.uid) {
      this.library.rebindUid(previousUid, profile.uid);
      this.studio.rebindCreatorUid(previousUid, profile.uid, profile.email);
    } else {
      // Same-uid draft sync only (no cross-uid merge without verified email).
      this.studio.rebindCreatorUid(user.uid, profile.uid, profile.email);
    }
    // Keep the creator entitled to their own live titles.
    const drafts = this.studio.listDrafts(profile.uid, profile.email);
    for (const draft of drafts) {
      if (draft.publishedTitleId) {
        this.library.grantOwnership(profile.uid, draft.publishedTitleId);
      }
    }
    // Anyone with live/submitted Studio work is already a creator — heal status
    // when catalogue restore / content approval skipped setCreatorStatus.
    const hasCreatorWork = drafts.some(
      (d) => d.status === 'live' || d.status === 'submitted' || Boolean(d.publishedTitleId),
    );
    let creatorStatus = profile.creatorStatus;
    if (
      hasCreatorWork &&
      (creatorStatus === 'none' || creatorStatus === 'pending')
    ) {
      const healed = this.profiles.setCreatorStatus(
        profile.uid,
        'approved',
        'system:/me',
        'Auto-approved from live/submitted Studio drafts',
      );
      creatorStatus = healed?.creatorStatus ?? 'approved';
    }
    return {
      uid: profile.uid,
      email: profile.email,
      displayName: profile.displayName,
      role: profile.role,
      creatorStatus,
      market: {
        code: 'ZM',
        label: 'Zambia',
        currency: 'ZMW',
      },
    };
  }

  @Post('creator-application')
  applyCreator(
    @CurrentUser() user: AuthUser,
    @Body() body: { displayName?: string },
  ) {
    const profile = this.profiles.applyCreator({
      uid: user.uid,
      email: user.email,
      displayName: body.displayName ?? user.displayName,
    });
    return {
      uid: profile.uid,
      email: profile.email,
      displayName: profile.displayName,
      role: profile.role,
      creatorStatus: profile.creatorStatus,
    };
  }
}
