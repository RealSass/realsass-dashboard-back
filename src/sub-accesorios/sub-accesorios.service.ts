// src/sub-accesorios/sub-accesorios.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreateSubAccesorioDto } from './dto/create-sub-accesorio.dto';
import { UpdateSubAccesorioDto } from './dto/update-sub-accesorio.dto';
import type { TenantContext } from '../tenant/tenant.interface';

@Injectable()
export class SubAccesoriosService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(dto: CreateSubAccesorioDto, ctx: TenantContext) {
    const sub = await this.prisma.subAccesorio.create({
      data: {
        nombre: dto.nombre,
        tipo: dto.tipo,
        descripcion: dto.descripcion,
        cantidad: dto.cantidad ?? 0,
        organizationId: ctx.organizationId,
        puntoDeVentaId: dto.puntoDeVentaId,
        colores: {
          create: dto.colores?.map((color) => ({ color })) ?? [],
        },
        imagenes: {
          create: dto.imagenes?.map((url, i) => ({ url, orden: i })) ?? [],
        },
      },
      include: { colores: true, imagenes: true },
    });

    await this.audit.log({
      action: 'sub_accesorio.create',
      entityType: 'SubAccesorio',
      entityId: sub.id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: { nombre: dto.nombre },
    });

    return sub;
  }

  async findAll(
    ctx: TenantContext,
    filters?: { nombre?: string; tipo?: string; puntoDeVentaId?: string },
  ) {
    return this.prisma.subAccesorio.findMany({
      where: {
        organizationId: ctx.organizationId,
        isActive: true,
        ...(filters?.nombre && {
          nombre: { contains: filters.nombre, mode: 'insensitive' },
        }),
        ...(filters?.tipo && { tipo: filters.tipo }),
        ...(filters?.puntoDeVentaId && {
          puntoDeVentaId: filters.puntoDeVentaId,
        }),
      },
      include: {
        colores: true,
        imagenes: { orderBy: { orden: 'asc' } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: string, ctx: TenantContext) {
    const sub = await this.prisma.subAccesorio.findFirst({
      where: { id, organizationId: ctx.organizationId },
      include: {
        colores: true,
        imagenes: { orderBy: { orden: 'asc' } },
      },
    });
    if (!sub) throw new NotFoundException('SubAccesorio no encontrado');
    return sub;
  }

  async update(id: string, dto: UpdateSubAccesorioDto, ctx: TenantContext) {
    await this.findOne(id, ctx);

    const sub = await this.prisma.subAccesorio.update({
      where: { id },
      data: {
        nombre: dto.nombre,
        tipo: dto.tipo,
        descripcion: dto.descripcion,
        cantidad: dto.cantidad,
        colores: dto.colores
          ? { deleteMany: {}, create: dto.colores.map((color) => ({ color })) }
          : undefined,
        imagenes: dto.imagenes
          ? {
              deleteMany: {},
              create: dto.imagenes.map((url, i) => ({ url, orden: i })),
            }
          : undefined,
      },
      include: { colores: true, imagenes: true },
    });

    await this.audit.log({
      action: 'sub_accesorio.update',
      entityType: 'SubAccesorio',
      entityId: id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: dto as Record<string, unknown>,
    });

    return sub;
  }

  async remove(id: string, ctx: TenantContext) {
    await this.findOne(id, ctx);

    await this.audit.log({
      action: 'sub_accesorio.delete',
      entityType: 'SubAccesorio',
      entityId: id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: {},
    });

    return this.prisma.subAccesorio.update({
      where: { id },
      data: { isActive: false },
      select: { id: true, nombre: true, isActive: true },
    });
  }
}
