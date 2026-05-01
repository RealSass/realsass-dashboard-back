// src/audit/audit.service.ts
import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export interface AuditLogInput {
  action: string;
  entityType: string;
  entityId?: string;
  userId?: string;
  organizationId?: string;
  payload?: Record<string, unknown>;
  ipAddress?: string;
  userAgent?: string;
}

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Registra una acción administrativa. Nunca lanza — falla silenciosamente
   * para no interrumpir el flujo principal.
   */
  async log(input: AuditLogInput): Promise<void> {
    try {
      await this.prisma.auditLog.create({
        data: {
          action: input.action,
          entityType: input.entityType,
          entityId: input.entityId,
          userId: input.userId,
          organizationId: input.organizationId,
          // Cast explícito: Record<string,unknown> → Prisma.InputJsonValue
          payload: (input.payload ?? {}) as Prisma.InputJsonValue,
          ipAddress: input.ipAddress,
          userAgent: input.userAgent,
        },
      });
    } catch {
      // Audit no debe romper el flujo principal
    }
  }
}
