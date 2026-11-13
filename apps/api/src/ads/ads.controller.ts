import { Body, Controller, Inject, Post, UseGuards } from '@nestjs/common';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { AdsService } from './ads.service';

@Controller('ads')
@UseGuards(AuthGuard)
export class AdsController {
  constructor(@Inject(AdsService) private readonly ads: AdsService) {}

  /** Record a verified completed ad event (prototype inventory). */
  @Post('complete')
  complete(
    @CurrentUser() user: AuthUser,
    @Body()
    body: {
      titleId?: string;
      placement?: 'preroll' | 'midroll';
      completedSec?: number;
      trackId?: string;
    },
  ) {
    return this.ads.complete({
      listenerUid: user.uid,
      titleId: body.titleId ?? '',
      placement: body.placement ?? 'preroll',
      completedSec: body.completedSec ?? 0,
      trackId: body.trackId,
    });
  }
}
