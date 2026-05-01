// src/tenant/tenant.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { TenantContext } from './tenant.interface';
import type { Request } from 'express';

/**
 * @TenantCtx() — inyecta el TenantContext en el parámetro del controller.
 * Requiere que TenantGuard haya corrido antes.
 *
 * Uso:
 *   @Get()
 *   findAll(@TenantCtx() ctx: TenantContext) { ... }
 */
export const TenantCtx = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): TenantContext => {
    const request = ctx.switchToHttp().getRequest<Request>();
    return (request as any).tenantContext as TenantContext;
  },
);
