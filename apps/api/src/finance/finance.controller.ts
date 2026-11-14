import { Controller, Get, Inject, Query, UseGuards } from '@nestjs/common';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import type { AuthUser } from '../auth/auth.types';
import { LedgerService } from './ledger.service';

@Controller('finance')
export class FinanceController {
  constructor(@Inject(LedgerService) private readonly ledger: LedgerService) {}

  /** Public catalogue of subscription plans (server-priced). */
  @Get('plans')
  listPlans(@Query('currency') currency?: string) {
    return { items: this.ledger.listPlans(currency?.trim().toUpperCase()) };
  }

  @Get('me/subscription')
  @UseGuards(AuthGuard)
  mySubscription(@CurrentUser() user: AuthUser) {
    const sub = this.ledger.getActiveSubscription(user.uid);
    return { subscription: sub ?? null };
  }

  /** Creator payable snapshot from the double-entry ledger (cashout foundation). */
  @Get('me/balances')
  @UseGuards(AuthGuard)
  myBalances(
    @CurrentUser() user: AuthUser,
    @Query('currency') currency?: string,
  ) {
    const snap = this.ledger.creatorBalance(
      user.uid,
      currency?.trim().toUpperCase() || 'ZMW',
    );
    return {
      ...snap,
      // Hold policy stays in Studio sales dashboard for now; cashout phase will unify.
      note: 'Payable is ledger liability. Holds/available split lands with cashout module.',
    };
  }
}
