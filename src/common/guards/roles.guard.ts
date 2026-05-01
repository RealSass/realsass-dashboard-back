// src/common/guards/roles.guard.ts
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from '../decorators/roles.decorator';
import type { TenantContext } from '../../tenant/tenant.interface';
import type { Request } from 'express';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<string[]>(
      ROLES_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!requiredRoles || requiredRoles.length === 0) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const tenant = (request as any).tenantContext as TenantContext | undefined;

    if (!tenant) {
      throw new ForbiddenException('Contexto de tenant no disponible');
    }

    if (!requiredRoles.includes(tenant.role)) {
      throw new ForbiddenException(
        'No tenés permisos para realizar esta acción',
      );
    }

    return true;
  }
}
