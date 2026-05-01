// src/common/decorators/current-user.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';

/**
 * @CurrentUser() — retorna el objeto user inyectado por FirebaseAuthGuard.
 * Contiene: { uid, email, firebaseUid }
 */
export const CurrentUser = createParamDecorator(
  (data: string | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest<Request>();
    const user = (request as any).user;
    return data ? user?.[data] : user;
  },
);
