import { Body, Controller, Get, Inject, Post, Query, UseGuards } from '@nestjs/common';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { AdsService } from './ads.service';

@Controller('ads')
export class AdsController {
  constructor(@Inject(AdsService) private readonly ads: AdsService) {}

  /** Active campaigns (network inventory until advertiser self-serve). */
  @Get('campaigns')
  campaigns() {
    return this.ads.listCampaigns();
  }

  /** Record a client-reported AdMob reward (paired with SSV when configured). */
  @Post('complete')
  @UseGuards(AuthGuard)
  complete(
    @CurrentUser() user: AuthUser,
    @Body()
    body: {
      titleId?: string;
      placement?: 'preroll' | 'midroll';
      completedSec?: number;
      trackId?: string;
      source?: string;
      rewardEarned?: boolean;
      campaignId?: string;
    },
  ) {
    return this.ads.complete({
      listenerUid: user.uid,
      titleId: body.titleId ?? '',
      placement: body.placement ?? 'preroll',
      completedSec: body.completedSec ?? 0,
      trackId: body.trackId,
      source: body.source ?? 'admob',
      rewardEarned: body.rewardEarned === true,
      campaignId: body.campaignId,
    });
  }

  /**
   * AdMob Server-Side Verification callback (no auth — signed by Google).
   * Set in AdMob console → ad unit → Server-side verification URL:
   *   https://<api-host>/v1/ads/ssv
   */
  @Get('ssv')
  ssvGet(@Query() query: Record<string, string>) {
    return this.ads.ssv(query);
  }

  @Post('ssv')
  ssvPost(@Query() query: Record<string, string>, @Body() body: Record<string, string>) {
    return this.ads.ssv({ ...body, ...query });
  }
}
