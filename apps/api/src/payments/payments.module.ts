import { Module } from '@nestjs/common';

import { CatalogueModule } from '../catalogue/catalogue.module';
import { FinanceModule } from '../finance/finance.module';
import { LibraryModule } from '../library/library.module';
import { StudioModule } from '../studio/studio.module';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { PaymentsStore } from './payments.store';

@Module({
  imports: [CatalogueModule, LibraryModule, FinanceModule, StudioModule],
  controllers: [PaymentsController],
  providers: [PaymentsService, PaymentsStore],
  exports: [PaymentsService, PaymentsStore],
})
export class PaymentsModule {}
