import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { NotesController } from './notes.controller';
import { NotesStore } from './notes.store';

@Module({
  imports: [AuthModule],
  controllers: [NotesController],
  providers: [NotesStore],
})
export class NotesModule {}
