// src/pdv/pdv.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreatePuntoDeVentaDto } from './dto/create-pdv.dto';
import { UpdatePuntoDeVentaDto } from './dto/update-pdv.dto';
import type { TenantContext } from '../tenant/tenant.interface';

@Injectable()
export class PuntoDeVentaService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(dto: CreatePuntoDeVentaDto, ctx: TenantContext) {
    const pdv = await this.prisma.puntoDeVenta.create({
      data: {
        nombre: dto.nombre,
        direccion: dto.direccion,
        ciudad: dto.ciudad,
        organizationId: ctx.organizationId,
      },
    });

    await this.audit.log({
      action: 'pdv.create',
      entityType: 'PuntoDeVenta',
      entityId: pdv.id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: { nombre: dto.nombre },
    });

    return pdv;
  }

  async findAll(ctx: TenantContext) {
    return this.prisma.puntoDeVenta.findMany({
      where: { organizationId: ctx.organizationId, isActive: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: string, ctx: TenantContext) {
    const pdv = await this.prisma.puntoDeVenta.findFirst({
      where: { id, organizationId: ctx.organizationId },
    });
    if (!pdv) throw new NotFoundException('Punto de venta no encontrado');
    return pdv;
  }

  async update(id: string, dto: UpdatePuntoDeVentaDto, ctx: TenantContext) {
    await this.findOne(id, ctx);

    const pdv = await this.prisma.puntoDeVenta.update({
      where: { id },
      data: {
        nombre: dto.nombre,
        direccion: dto.direccion,
        ciudad: dto.ciudad,
      },
    });

    await this.audit.log({
      action: 'pdv.update',
      entityType: 'PuntoDeVenta',
      entityId: id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: dto as Record<string, unknown>,
    });

    return pdv;
  }

  async remove(id: string, ctx: TenantContext) {
    await this.findOne(id, ctx);

    await this.audit.log({
      action: 'pdv.delete',
      entityType: 'PuntoDeVenta',
      entityId: id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: {},
    });

    return this.prisma.puntoDeVenta.update({
      where: { id },
      data: { isActive: false },
      select: { id: true, nombre: true, isActive: true },
    });
  }
}
