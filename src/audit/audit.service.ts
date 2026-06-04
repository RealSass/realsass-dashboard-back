// src/audit/audit.service.ts
//
// Escribe entradas en la tabla audit_logs de forma asíncrona (fire-and-forget).
// Los errores se loguean pero nunca propagan — un fallo de auditoría no debe
// romper la operación de negocio que lo disparó.

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface AuditLogParams {
  action:          string;        // ej: 'propiedad.create', 'zona.delete'
  entityType:      string;        // ej: 'Propiedad', 'Zona', 'User'
  entityId?:       string | null;
  userId?:         string | null;
  organizationId?: string | null;
  payload?:        Record<string, unknown>;
  ipAddress?:      string | null;
  userAgent?:      string | null;
}

@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Registra una entrada de auditoría de forma asíncrona.
   * Fire-and-forget: nunca lanza excepciones al caller.
   */
  log(params: AuditLogParams): void {
    const {
      action,
      entityType,
      entityId    = null,
      userId      = null,
      organizationId = null,
      payload     = {},
      ipAddress   = null,
      userAgent   = null,
    } = params;

    this.prisma.auditLog
      .create({
        data: {
          action,
          entityType,
          entityId,
          userId,
          organizationId,
          payload,
          ipAddress,
          userAgent,
        },
      })
      .catch((err: unknown) => {
        // Loguear sin relanzar — el audit nunca debe bloquear el flujo principal
        this.logger.error(
          `Error registrando audit log [${action}]: ${(err as Error).message}`,
        );
      });
  }

  /**
   * Versión async para cuando necesitás await (ej: tests, scripts).
   * En producción preferir log() para no añadir latencia.
   */
  async logAsync(params: AuditLogParams): Promise<void> {
    try {
      await this.prisma.auditLog.create({
        data: {
          action:         params.action,
          entityType:     params.entityType,
          entityId:       params.entityId       ?? null,
          userId:         params.userId         ?? null,
          organizationId: params.organizationId ?? null,
          payload:        params.payload        ?? {},
          ipAddress:      params.ipAddress      ?? null,
          userAgent:      params.userAgent      ?? null,
        },
      });
    } catch (err: unknown) {
      this.logger.error(
        `Error registrando audit log [${params.action}]: ${(err as Error).message}`,
      );
    }
  }
}
