import { Controller, Get, Inject } from '@nestjs/common';
import { networkInterfaces } from 'os';

import { DbService } from '../db/db.service';
import { FirestoreService } from '../db/firestore.service';

@Controller('health')
export class HealthController {
  constructor(
    @Inject(DbService) private readonly db: DbService,
    @Inject(FirestoreService) private readonly firestore: FirestoreService,
  ) {}

  @Get()
  async check() {
    const database = await this.db.health();
    const port = Number(process.env.PORT ?? 3001);
    const lanHosts = this.lanIpv4().map((ip) => `http://${ip}:${port}/v1`);
    const backend = this.db.backendPreference;
    const data =
      backend === 'firestore'
        ? {
            backend: 'firestore' as const,
            connected: this.firestore.enabled,
            detail: this.firestore.enabled
              ? 'ok'
              : 'not connected — need FIREBASE_SERVICE_ACCOUNT_JSON or ADC',
          }
        : {
            backend: backend === 'disk' ? ('disk' as const) : ('postgres' as const),
            connected: database.ok,
            detail: database.detail,
          };

    return {
      status: data.connected || backend === 'disk' ? 'ok' : 'degraded',
      service: 'listen-api',
      time: new Date().toISOString(),
      port,
      lanHosts,
      authMode: (process.env.AUTH_MODE ?? 'hybrid').toLowerCase(),
      paymentsMode: (process.env.PAYMENTS_MODE ?? 'simulate').toLowerCase(),
      data,
      database: {
        connected: data.connected,
        detail: data.detail,
        backend: data.backend,
      },
    };
  }

  private lanIpv4(): string[] {
    const nets = networkInterfaces();
    const out: string[] = [];
    for (const entries of Object.values(nets)) {
      if (!entries) continue;
      for (const entry of entries) {
        if (entry.internal) continue;
        if (entry.family !== 'IPv4' && (entry.family as unknown) !== 4) continue;
        out.push(entry.address);
      }
    }
    return out;
  }
}
