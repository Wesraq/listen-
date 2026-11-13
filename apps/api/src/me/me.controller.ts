import { Body, Controller, Get, Inject, Post, UseGuards } from '@nestjs/common';

import { AdminStore } from '../admin/admin.store';
import { AuthGuard } from '../auth/auth.guard';
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
  ) {}

  @Get()
  me(@CurrentUser() user: AuthUser) {
    const existing = this.profiles.findUser(user.uid, user.email);
    const previousUid = existing?.uid;
    const profile = this.profiles.ensureConsumer({
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
    });
    if (previousUid && previousUid !== profile.uid) {
      this.library.rebindUid(previousUid, profile.uid);
    }
    // Always rebind Studio drafts for this email/uid so Content appears after login.
    this.studio.rebindCreatorUid(previousUid ?? user.uid, profile.uid, profile.email);
    // Keep the creator entitled to their own live titles.
    for (const draft of this.studio.listDrafts(profile.uid, profile.email)) {
      if (draft.publishedTitleId) {
        this.library.grantOwnership(profile.uid, draft.publishedTitleId);
      }
    }
    return {
      uid: profile.uid,
      email: profile.email,
      displayName: profile.displayName,
      role: profile.role,
      creatorStatus: profile.creatorStatus,
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
