// src/tenant/tenant.guard.ts
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  BadRequestException,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { Request } from 'express';
import type { TenantContext } from './tenant.interface';

@Injectable()
export class TenantGuard implements CanActivate {
  private readonly logger = new Logger(TenantGuard.name);

  constructor(private readonly prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const organizationId = request.headers['x-organization-id'] as string;

    if (!organizationId) {
      throw new BadRequestException(
        'Header x-organization-id requerido',
      );
    }

    const firebaseUid = (request as any).user?.firebaseUid as string;
    if (!firebaseUid) {
      throw new UnauthorizedException('Usuario no autenticado');
    }

    // Verificar que el usuario existe y está activo
    const user = await this.prisma.user.findUnique({
      where: { firebaseUid },
      select: { id: true, role: true, isActive: true },
    });

    if (!user || !user.isActive) {
      throw new UnauthorizedException('Usuario inactivo o no encontrado');
    }

    // Verificar que la organización existe y está activa
    const org = await this.prisma.organization.findUnique({
      where: { id: organizationId },
      select: { id: true, isActive: true },
    });

    if (!org || !org.isActive) {
      throw new BadRequestException('Organización inválida o inactiva');
    }

    // Inyectar TenantContext en el request
    const tenantCtx: TenantContext = {
      userId: user.id,
      organizationId,
      role: user.role,
      firebaseUid,
    };
    (request as any).tenantContext = tenantCtx;

    return true;
  }
}
