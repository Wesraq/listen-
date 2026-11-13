import {
  BadRequestException,
  Body,
  Controller,
  Headers,
  Inject,
  Param,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { PaymentsService } from './payments.service';

@Controller('payments')
export class PaymentsController {
  constructor(@Inject(PaymentsService) private readonly payments: PaymentsService) {}

  /** Create a payment intent for a paid title (server-priced). */
  @Post('intents')
  @UseGuards(AuthGuard)
  createIntent(@CurrentUser() user: AuthUser, @Body() body: { titleId?: string }) {
    if (!body?.titleId?.trim()) {
      throw new BadRequestException('titleId is required');
    }
    return this.payments.createIntent(user.uid, body.titleId.trim());
  }

  /**
   * Confirm a simulated payment (PAYMENTS_MODE=simulate).
   * Grants entitlement server-side — clients must not invent ownership.
   */
  @Post('intents/:id/confirm')
  @UseGuards(AuthGuard)
  confirm(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.payments.confirmSimulated(user.uid, id);
  }

  /**
   * Provider webhook. Prefer raw body for HMAC; Nest JSON body is re-stringified
   * when raw is unavailable (acceptable for the simulate prototype).
   */
  @Post('webhooks')
  webhook(
    @Req() req: Request & { rawBody?: Buffer | string; body?: unknown },
    @Headers('x-listen-signature') listenSig?: string,
    @Headers('x-webhook-signature') webhookSig?: string,
    @Headers('x-event-id') eventId?: string,
  ) {
    const raw =
      typeof req.rawBody === 'string'
        ? req.rawBody
        : Buffer.isBuffer(req.rawBody)
          ? req.rawBody.toString('utf8')
          : JSON.stringify(req.body ?? {});
    return this.payments.handleWebhook(raw, listenSig || webhookSig, eventId);
  }
}
