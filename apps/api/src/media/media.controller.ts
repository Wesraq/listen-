import {
  Controller,
  ForbiddenException,
  Get,
  Headers,
  Inject,
  Param,
  Post,
  Query,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Response } from 'express';

import { AuthGuard } from '../auth/auth.guard';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { CatalogueService } from '../catalogue/catalogue.service';
import { LibraryService } from '../library/library.service';
import { MediaSigningService } from './media-signing.service';
import { MediaStore } from './media.store';

@Controller('media')
export class MediaController {
  constructor(
    @Inject(MediaStore) private readonly media: MediaStore,
    @Inject(MediaSigningService) private readonly signing: MediaSigningService,
    @Inject(AuthService) private readonly auth: AuthService,
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(LibraryService) private readonly library: LibraryService,
  ) {}

  /** Upload creator audio/ebook bytes (Firebase Storage when cloud-backed). */
  @Post()
  @UseGuards(AuthGuard)
  @UseInterceptors(
    FileInterceptor('file', {
      limits: { fileSize: 120 * 1024 * 1024 },
    }),
  )
  async upload(
    @CurrentUser() user: AuthUser,
    @UploadedFile()
    file?: {
      buffer: Buffer;
      originalname?: string;
      mimetype?: string;
      size?: number;
    },
  ) {
    if (!file?.buffer?.length) {
      throw new BadRequestException('Missing file upload (field name: file)');
    }
    const meta = await this.media.save({
      buffer: file.buffer,
      originalName: file.originalname || 'upload.bin',
      mimeType: file.mimetype,
      creatorUid: user.uid,
    });
    const signed = this.signing.sign(meta.id);
    return {
      id: meta.id,
      originalName: meta.originalName,
      bytes: meta.bytes,
      mimeType: meta.mimeType,
      url: signed.url,
      exp: signed.exp,
      sig: signed.sig,
    };
  }

  /** Issue a short-lived signed URL — creator or entitled listener only. */
  @Post(':id/sign')
  @UseGuards(AuthGuard)
  async sign(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    await this.assertCanAccessMedia(user, id);
    const signed = this.signing.sign(id);
    return { id, ...signed, requester: user.uid };
  }

  /**
   * Public sign for free / free-with-ads catalogue media (guest playback).
   * Paid titles still require a normal authenticated `/sign`.
   */
  @Post(':id/sign-free')
  async signFree(@Param('id') id: string) {
    if (!this.isFreeMedia(id)) {
      throw new ForbiddenException('Only free titles can be signed without auth');
    }
    // Ensure the object exists (recovers Storage-only uploads).
    await this.media.ensureMeta(id);
    const signed = this.signing.sign(id);
    return { id, ...signed, requester: 'guest' };
  }

  /**
   * Stream uploaded media. Requires a valid signature when signing is enabled
   * (default on Cloud Run). Free catalogue media may stream without a signature.
   */
  @Get(':id')
  async stream(
    @Param('id') id: string,
    @Query('exp') exp: string | undefined,
    @Query('sig') sig: string | undefined,
    @Headers('authorization') authorization: string | undefined,
    @Res() res: Response,
  ) {
    const free = this.isFreeMedia(id);
    if (this.signing.requireSigned()) {
      if (!free) {
        this.signing.assertValid(id, exp, sig);
      }
    } else {
      // When signing is off (local LAN), still require auth + entitlement.
      const user = await this.auth.resolveUser(authorization);
      await this.assertCanAccessMedia(user, id);
    }

    const { meta, stream } = await this.media.open(id);
    res.status(200);
    res.setHeader('Content-Type', meta.mimeType || 'application/octet-stream');
    if (meta.bytes > 0) {
      res.setHeader('Content-Length', String(meta.bytes));
    }
    res.setHeader(
      'Content-Disposition',
      `inline; filename="${encodeURIComponent(meta.originalName)}"`,
    );
    res.setHeader('Cache-Control', free ? 'public, max-age=300' : 'private, max-age=300');
    stream.on('error', () => {
      if (!res.headersSent) {
        res.status(404).json({ message: 'Media file missing' });
      } else {
        res.end();
      }
    });
    stream.pipe(res);
  }

  private isFreeMedia(mediaId: string): boolean {
    const titleId = this.catalogue.findTitleIdByMediaId(mediaId);
    if (!titleId) return false;
    try {
      const title = this.catalogue.getTitle(titleId);
      return title.priceMinor === 0 || title.monetisationMode === 'free_with_ads';
    } catch {
      return false;
    }
  }

  private async assertCanAccessMedia(user: AuthUser, mediaId: string) {
    const titleId = this.catalogue.findTitleIdByMediaId(mediaId);
    if (titleId) {
      const entitlement = this.library.entitlement(user.uid, titleId);
      if (entitlement.entitled) return;
      throw new ForbiddenException('Not entitled to this media');
    }

    const meta = await this.media.ensureMeta(mediaId);
    if (meta.creatorUid && meta.creatorUid === user.uid) return;

    // Orphan upload: only the creator (or no creatorUid → deny on cloud).
    if (!meta.creatorUid) {
      throw new ForbiddenException('Media is not linked to an entitled title');
    }
    throw new ForbiddenException('Not entitled to this media');
  }
}
