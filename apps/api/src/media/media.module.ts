import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { CatalogueModule } from '../catalogue/catalogue.module';
import { LibraryModule } from '../library/library.module';
import { MediaSigningService } from './media-signing.service';
import { MediaController } from './media.controller';
import { MediaStore } from './media.store';

@Module({
  imports: [AuthModule, CatalogueModule, LibraryModule],
  controllers: [MediaController],
  providers: [MediaStore, MediaSigningService],
  exports: [MediaStore, MediaSigningService],
})
export class MediaModule {}
