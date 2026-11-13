import {
  CanActivate,
  ExecutionContext,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';

import { AuthService } from './auth.service';
import { AuthUser } from './auth.types';

export const AUTH_USER_KEY = 'authUser';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<{
      headers: { authorization?: string };
      [AUTH_USER_KEY]?: AuthUser;
    }>();

    const user = await this.auth.resolveUser(request.headers.authorization);
    request[AUTH_USER_KEY] = user;
    return true;
  }
}
