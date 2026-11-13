import { Module } from '@nestjs/common';

import { CatalogueModule } from '../catalogue/catalogue.module';
import { LibraryModule } from '../library/library.module';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { PaymentsStore } from './payments.store';

@Module({
  imports: [CatalogueModule, LibraryModule],
  controllers: [PaymentsController],
  providers: [PaymentsService, PaymentsStore],
  exports: [PaymentsService, PaymentsStore],
})
export class PaymentsModule {}
