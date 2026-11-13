import { Module } from '@nestjs/common';

import { CatalogueModule } from '../catalogue/catalogue.module';
import { LibraryModule } from '../library/library.module';
import { StudioModule } from '../studio/studio.module';
import { AdminController } from './admin.controller';
import { AdminGuard } from './admin.guard';
import { AdminStore } from './admin.store';
import { CatalogueRestoreService } from './catalogue-restore.service';

@Module({
  imports: [StudioModule, CatalogueModule, LibraryModule],
  controllers: [AdminController],
  providers: [AdminStore, AdminGuard, CatalogueRestoreService],
  exports: [AdminStore],
})
export class AdminModule {}
