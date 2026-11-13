import {
  Controller,
  Get,
  Inject,
  Param,
  Post,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Response } from 'express';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { MediaStore } from './media.store';

@Controller('media')
export class MediaController {
  constructor(@Inject(MediaStore) private readonly media: MediaStore) {}

  /** Upload creator audio/ebook bytes (prototype disk store). */
  @Post()
  @UseGuards(AuthGuard)
  @UseInterceptors(
    FileInterceptor('file', {
      limits: { fileSize: 120 * 1024 * 1024 },
    }),
  )
  upload(
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
    const meta = this.media.save({
      buffer: file.buffer,
      originalName: file.originalname || 'upload.bin',
      mimeType: file.mimetype,
      creatorUid: user.uid,
    });
    return {
      id: meta.id,
      originalName: meta.originalName,
      bytes: meta.bytes,
      mimeType: meta.mimeType,
      url: `/v1/media/${meta.id}`,
    };
  }

  /** Stream uploaded media for the player (LAN prototype — no signed URLs yet). */
  @Get(':id')
  stream(@Param('id') id: string, @Res() res: Response) {
    const { meta, stream } = this.media.open(id);
    res.status(200);
    res.setHeader('Content-Type', meta.mimeType || 'application/octet-stream');
    res.setHeader('Content-Length', String(meta.bytes));
    res.setHeader(
      'Content-Disposition',
      `inline; filename="${encodeURIComponent(meta.originalName)}"`,
    );
    res.setHeader('Cache-Control', 'private, max-age=3600');
    stream.on('error', () => {
      if (!res.headersSent) {
        res.status(404).json({ message: 'Media file missing' });
      } else {
        res.end();
      }
    });
    stream.pipe(res);
  }
}
