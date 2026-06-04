// src/audit/audit.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export interface AuditLogParams {
  action:          string;
  entityType:      string;
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

  /** Fire-and-forget — nunca lanza excepciones al caller */
  log(params: AuditLogParams): void {
    const data = this.buildData(params);
    this.prisma.auditLog
      .create({ data })
      .catch((err: unknown) => {
        this.logger.error(
          `Error registrando audit log [${params.action}]: ${(err as Error).message}`,
        );
      });
  }

  /** Versión async para tests o scripts donde necesitás await */
  async logAsync(params: AuditLogParams): Promise<void> {
    try {
      await this.prisma.auditLog.create({ data: this.buildData(params) });
    } catch (err: unknown) {
      this.logger.error(
        `Error registrando audit log [${params.action}]: ${(err as Error).message}`,
      );
    }
  }

  private buildData(
    params: AuditLogParams,
  ): Prisma.AuditLogCreateInput {
    return {
      action:    params.action,
      entityType: params.entityType,
      entityId:  params.entityId  ?? null,
      ipAddress: params.ipAddress ?? null,
      userAgent: params.userAgent ?? null,
      // Prisma v7: campo Json requiere cast explícito a InputJsonValue
      payload:   (params.payload ?? {}) as Prisma.InputJsonValue,
      ...(params.userId && {
        user: { connect: { id: params.userId } },
      }),
      ...(params.organizationId && {
        organization: { connect: { id: params.organizationId } },
      }),
    };
  }
}
