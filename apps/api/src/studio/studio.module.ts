import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { CatalogueModule } from '../catalogue/catalogue.module';
import { FinanceModule } from '../finance/finance.module';
import { StudioController } from './studio.controller';
import { StudioStore } from './studio.store';

@Module({
  imports: [AuthModule, CatalogueModule, FinanceModule],
  controllers: [StudioController],
  providers: [StudioStore],
  exports: [StudioStore],
})
export class StudioModule {}
