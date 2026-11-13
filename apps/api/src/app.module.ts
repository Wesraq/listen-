import { Module } from '@nestjs/common';

import { AdminModule } from './admin/admin.module';
import { AdsModule } from './ads/ads.module';
import { AuthModule } from './auth/auth.module';
import { CatalogueModule } from './catalogue/catalogue.module';
import { ConsumptionModule } from './consumption/consumption.module';
import { DbModule } from './db/db.module';
import { HealthModule } from './health/health.module';
import { LibraryModule } from './library/library.module';
import { MeModule } from './me/me.module';
import { MediaModule } from './media/media.module';
import { NotesModule } from './notes/notes.module';
import { StudioModule } from './studio/studio.module';

@Module({
  imports: [
    DbModule,
    HealthModule,
    AuthModule,
    CatalogueModule,
    LibraryModule,
    MeModule,
    StudioModule,
    NotesModule,
    AdminModule,
    AdsModule,
    ConsumptionModule,
    MediaModule,
  ],
})
export class AppModule {}


