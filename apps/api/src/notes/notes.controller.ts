import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Inject,
  NotFoundException,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { NotesStore } from './notes.store';
import { NoteAnchor, NoteKind } from './notes.types';

@Controller('notes')
@UseGuards(AuthGuard)
export class NotesController {
  constructor(@Inject(NotesStore) private readonly notes: NotesStore) {}

  @Get()
  list(@CurrentUser() user: AuthUser, @Query('titleId') titleId?: string) {
    return { items: this.notes.list(user.uid, titleId) };
  }

  @Post()
  create(
    @CurrentUser() user: AuthUser,
    @Body()
    body: {
      titleId?: string;
      kind?: NoteKind;
      anchor?: NoteAnchor;
      locationId?: string;
      position?: number;
      text?: string;
      voiceDurationSec?: number;
      voiceRef?: string;
    },
  ) {
    if (!body.titleId || !body.locationId || !body.kind || !body.anchor) {
      throw new BadRequestException('titleId, locationId, kind and anchor are required');
    }
    try {
      return this.notes.create({
        uid: user.uid,
        titleId: body.titleId,
        kind: body.kind,
        anchor: body.anchor,
        locationId: body.locationId,
        position: body.position ?? 0,
        text: body.text,
        voiceDurationSec: body.voiceDurationSec,
        voiceRef: body.voiceRef,
      });
    } catch (error) {
      throw new BadRequestException(error instanceof Error ? error.message : 'Invalid note');
    }
  }

  @Delete(':id')
  remove(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    if (!this.notes.remove(user.uid, id)) throw new NotFoundException('Note not found');
    return { ok: true };
  }
}
