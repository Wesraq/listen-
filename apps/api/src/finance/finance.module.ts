import { Module } from '@nestjs/common';

import { FinanceController } from './finance.controller';
import { LedgerService } from './ledger.service';
import { LedgerStore } from './ledger.store';
import { ReconciliationService } from './reconciliation.service';
import { ReconciliationStore } from './reconciliation.store';

@Module({
  controllers: [FinanceController],
  providers: [LedgerStore, LedgerService, ReconciliationStore, ReconciliationService],
  exports: [LedgerStore, LedgerService, ReconciliationStore, ReconciliationService],
})
export class FinanceModule {}
