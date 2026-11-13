import {
  Controller,
  ForbiddenException,
  Get,
  Inject,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { LibraryService } from './library.service';

@Controller('library')
@UseGuards(AuthGuard)
export class LibraryController {
  constructor(@Inject(LibraryService) private readonly library: LibraryService) {}

  @Get()
  getLibrary(@CurrentUser() user: AuthUser) {
    return this.library.getLibrary(user.uid);
  }

  @Get('entitlements/:titleId')
  entitlement(@CurrentUser() user: AuthUser, @Param('titleId') titleId: string) {
    return this.library.entitlement(user.uid, titleId);
  }

  /**
   * Legacy client grant. Prefer POST /payments/intents + confirm/webhook.
   * Disabled when ALLOW_CLIENT_GRANTS=false.
   */
  @Post('owned/:titleId')
  grant(@CurrentUser() user: AuthUser, @Param('titleId') titleId: string) {
    const allow = (process.env.ALLOW_CLIENT_GRANTS ?? 'false').toLowerCase() === 'true';
    if (!allow) {
      throw new ForbiddenException(
        'Client grants disabled. Create a payment intent and confirm via /payments.',
      );
    }
    return this.library.grant(user.uid, titleId);
  }

  @Post('saved/:titleId')
  toggleSave(@CurrentUser() user: AuthUser, @Param('titleId') titleId: string) {
    return this.library.toggleSave(user.uid, titleId);
  }
}
