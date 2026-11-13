import { Module } from '@nestjs/common';

import { CatalogueController } from './catalogue.controller';
import { CatalogueService } from './catalogue.service';
import { CatalogueStore } from './catalogue.store';

@Module({
  controllers: [CatalogueController],
  providers: [CatalogueStore, CatalogueService],
  exports: [CatalogueService, CatalogueStore],
})
export class CatalogueModule {}
