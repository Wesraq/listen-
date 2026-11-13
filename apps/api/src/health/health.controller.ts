import { Controller, Get, Inject } from '@nestjs/common';

import { DbService } from '../db/db.service';

@Controller('health')
export class HealthController {
  constructor(@Inject(DbService) private readonly db: DbService) {}

  @Get()
  async check() {
    const database = await this.db.health();
    return {
      status: database.ok ? 'ok' : 'degraded',
      service: 'listen-api',
      time: new Date().toISOString(),
      database: {
        connected: database.ok,
        detail: database.detail,
      },
    };
  }
}
