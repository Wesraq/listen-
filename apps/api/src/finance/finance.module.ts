import { Module } from '@nestjs/common';

import { FinanceController } from './finance.controller';
import { LedgerService } from './ledger.service';
import { LedgerStore } from './ledger.store';

@Module({
  controllers: [FinanceController],
  providers: [LedgerStore, LedgerService],
  exports: [LedgerStore, LedgerService],
})
export class FinanceModule {}
