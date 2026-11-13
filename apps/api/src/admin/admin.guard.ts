import {
  CanActivate,
  ExecutionContext,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';

import { AdminStore } from './admin.store';
import { AdminSession } from './admin.types';

export const ADMIN_SESSION_KEY = 'adminSession';

@Injectable()
export class AdminGuard implements CanActivate {
  constructor(@Inject(AdminStore) private readonly store: AdminStore) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<{
      headers: { authorization?: string };
      [ADMIN_SESSION_KEY]?: AdminSession;
    }>();
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing admin Bearer token');
    }
    const token = header.slice('Bearer '.length).trim();
    const session = this.store.resolveSession(token);
    if (!session) {
      throw new UnauthorizedException('Invalid or expired admin session');
    }
    request[ADMIN_SESSION_KEY] = session;
    return true;
  }
}
