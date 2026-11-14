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
import type { PaymentKind, PaymentProvider } from '../finance/finance.types';
import { PaymentsService } from './payments.service';

@Controller('payments')
export class PaymentsController {
  constructor(@Inject(PaymentsService) private readonly payments: PaymentsService) {}

  /**
   * Create a payment intent for a title purchase or Listen+ subscription.
   * Server prices the amount — clients must not send amountMinor.
   */
  @Post('intents')
  @UseGuards(AuthGuard)
  createIntent(
    @CurrentUser() user: AuthUser,
    @Body()
    body: {
      kind?: PaymentKind;
      titleId?: string;
      planId?: string;
      provider?: PaymentProvider | string;
      payerPhone?: string;
    },
  ) {
    if (!body?.titleId?.trim() && !body?.planId?.trim()) {
      throw new BadRequestException('titleId or planId is required');
    }
    return this.payments.createIntent(user.uid, {
      kind: body.kind,
      titleId: body.titleId,
      planId: body.planId,
      provider: body.provider as PaymentProvider | undefined,
      payerPhone: body.payerPhone,
    });
  }

  /**
   * Confirm a simulated / sandbox payment (PAYMENTS_MODE=simulate).
   * Posts the shared ledger settlement and activates access server-side.
   */
  @Post('intents/:id/confirm')
  @UseGuards(AuthGuard)
  confirm(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.payments.confirmSimulated(user.uid, id);
  }

  /**
   * Provider webhook (MTN MoMo / Airtel / card processor).
   * Prefer raw body for HMAC; Nest JSON body is re-stringified when raw is unavailable.
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
