import { Module } from '@nestjs/common';

import { CatalogueModule } from '../catalogue/catalogue.module';
import { StudioModule } from '../studio/studio.module';
import { LibraryController } from './library.controller';
import { LibraryService } from './library.service';
import { LibraryStore } from './library.store';

@Module({
  imports: [CatalogueModule, StudioModule],
  controllers: [LibraryController],
  providers: [LibraryService, LibraryStore],
  exports: [LibraryService, LibraryStore],
})
export class LibraryModule {}
