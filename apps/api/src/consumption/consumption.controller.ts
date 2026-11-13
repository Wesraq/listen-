import { Body, Controller, Inject, Post, UseGuards } from '@nestjs/common';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { ConsumptionService } from './consumption.service';

@Controller('consumption')
@UseGuards(AuthGuard)
export class ConsumptionController {
  constructor(@Inject(ConsumptionService) private readonly consumption: ConsumptionService) {}

  @Post('qualified')
  qualified(
    @CurrentUser() user: AuthUser,
    @Body()
    body: {
      titleId?: string;
      minutes?: number;
      kind?: 'listening' | 'reading';
    },
  ) {
    return this.consumption.creditQualified({
      listenerUid: user.uid,
      titleId: body.titleId ?? '',
      minutes: body.minutes ?? 0,
      kind: body.kind ?? 'listening',
    });
  }
}
