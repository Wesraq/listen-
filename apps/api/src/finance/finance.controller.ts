import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Inject,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import type { AuthUser } from '../auth/auth.types';
import type { CashoutRail } from './finance.types';
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

  /** Creator payable snapshot from the double-entry ledger. */
  @Get('me/balances')
  @UseGuards(AuthGuard)
  myBalances(
    @CurrentUser() user: AuthUser,
    @Query('currency') currency?: string,
  ) {
    return this.ledger.creatorBalance(
      user.uid,
      currency?.trim().toUpperCase() || 'ZMW',
    );
  }

  @Get('me/cashouts')
  @UseGuards(AuthGuard)
  myCashouts(@CurrentUser() user: AuthUser) {
    return { items: this.ledger.listCashoutsForCreator(user.uid) };
  }

  @Post('me/cashouts')
  @UseGuards(AuthGuard)
  requestCashout(
    @CurrentUser() user: AuthUser,
    @Body()
    body: {
      amountMinor?: number;
      currency?: string;
      rail?: CashoutRail | string;
      destination?: string;
    },
  ) {
    const amountMinor = Math.floor(Number(body.amountMinor));
    if (!Number.isFinite(amountMinor) || amountMinor <= 0) {
      throw new BadRequestException('amountMinor is required');
    }
    const rail = this.normalizeRail(body.rail);
    const destination = body.destination?.trim();
    if (!destination) {
      throw new BadRequestException('destination is required (MoMo number or bank reference)');
    }
    return this.ledger.requestCashout({
      creatorUid: user.uid,
      creatorName: user.displayName || user.email || user.uid,
      creatorEmail: user.email,
      amountMinor,
      currency: body.currency,
      rail,
      destination,
    });
  }

  private normalizeRail(raw?: string): CashoutRail {
    const value = (raw ?? 'mtn_momo').trim().toLowerCase();
    if (value === 'airtel_money' || value === 'airtel') return 'airtel_money';
    if (value === 'bank' || value === 'bank_transfer') return 'bank';
    return 'mtn_momo';
  }
}
