import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { MediaController } from './media.controller';
import { MediaStore } from './media.store';

@Module({
  imports: [AuthModule],
  controllers: [MediaController],
  providers: [MediaStore],
  exports: [MediaStore],
})
export class MediaModule {}
