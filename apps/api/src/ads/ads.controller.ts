import {
  Body,
  Controller,
  Get,
  Inject,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { AdsService } from './ads.service';

function rawQueryFromRequest(req: Request): string {
  const url = req.originalUrl || req.url || '';
  const q = url.includes('?') ? url.slice(url.indexOf('?') + 1) : '';
  return q;
}

@Controller('ads')
export class AdsController {
  constructor(@Inject(AdsService) private readonly ads: AdsService) {}

  @Get('campaigns')
  campaigns() {
    return this.ads.listCampaigns();
  }

  /**
   * Client UX / telemetry only. Does not settle advertising payables.
   * `rewardEarned` is ignored for money movement.
   */
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
   * AdMob Server-Side Verification (signature required).
   * Set in AdMob console → ad unit → SSV URL:
   *   https://<api-host>/v1/ads/ssv
   */
  @Get('ssv')
  ssvGet(@Query() query: Record<string, string>, @Req() req: Request) {
    return this.ads.ssv({
      query,
      rawQuery: rawQueryFromRequest(req),
    });
  }

  @Post('ssv')
  ssvPost(
    @Query() query: Record<string, string>,
    @Body() body: Record<string, string>,
    @Req() req: Request,
  ) {
    const merged = { ...body, ...query };
    // Prefer original URL query for signature; fall back to reconstructed order if needed.
    let raw = rawQueryFromRequest(req);
    if (!raw.includes('signature=') && merged.signature) {
      const params = new URLSearchParams();
      for (const [k, v] of Object.entries(merged)) {
        if (k === 'signature' || k === 'key_id') continue;
        if (v != null) params.set(k, String(v));
      }
      params.set('signature', String(merged.signature));
      if (merged.key_id) params.set('key_id', String(merged.key_id));
      raw = params.toString();
    }
    return this.ads.ssv({ query: merged, rawQuery: raw });
  }
}
