import { Global, Module } from '@nestjs/common';

import { DbService } from './db.service';
import { FirestoreService } from './firestore.service';

@Global()
@Module({
  providers: [DbService, FirestoreService],
  exports: [DbService, FirestoreService],
})
export class DbModule {}
