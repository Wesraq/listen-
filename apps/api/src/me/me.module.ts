import { Module } from '@nestjs/common';

import { AdminModule } from '../admin/admin.module';
import { LibraryModule } from '../library/library.module';
import { StudioModule } from '../studio/studio.module';
import { MeController } from './me.controller';

@Module({
  imports: [AdminModule, LibraryModule, StudioModule],
  controllers: [MeController],
})
export class MeModule {}
