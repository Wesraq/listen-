import { createParamDecorator, ExecutionContext } from '@nestjs/common';

import { AUTH_USER_KEY } from './auth.guard';
import { AuthUser } from './auth.types';

export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthUser => {
    const request = context.switchToHttp().getRequest<Record<string, unknown>>();
    return request[AUTH_USER_KEY] as AuthUser;
  },
);
