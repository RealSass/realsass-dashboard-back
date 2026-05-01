// src/accesorios/accesorios.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreateAccesorioDto } from './dto/create-accesorio.dto';
import { UpdateAccesorioDto } from './dto/update-accesorio.dto';
import type { TenantContext } from '../tenant/tenant.interface';

@Injectable()
export class AccesoriosService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(dto: CreateAccesorioDto, ctx: TenantContext) {
    const accesorio = await this.prisma.accesorio.create({
      data: {
        nombre: dto.nombre,
        modelo: dto.modelo,
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
      action: 'accesorio.create',
      entityType: 'Accesorio',
      entityId: accesorio.id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: { nombre: dto.nombre, tipo: dto.tipo },
    });

    return accesorio;
  }

  async findAll(
    ctx: TenantContext,
    filters?: { nombre?: string; tipo?: string; puntoDeVentaId?: string },
  ) {
    return this.prisma.accesorio.findMany({
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
    const accesorio = await this.prisma.accesorio.findFirst({
      where: { id, organizationId: ctx.organizationId },
      include: {
        colores: true,
        imagenes: { orderBy: { orden: 'asc' } },
      },
    });
    if (!accesorio) throw new NotFoundException('Accesorio no encontrado');
    return accesorio;
  }

  async update(id: string, dto: UpdateAccesorioDto, ctx: TenantContext) {
    await this.findOne(id, ctx);

    const accesorio = await this.prisma.accesorio.update({
      where: { id },
      data: {
        nombre: dto.nombre,
        modelo: dto.modelo,
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
      action: 'accesorio.update',
      entityType: 'Accesorio',
      entityId: id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: dto as Record<string, unknown>,
    });

    return accesorio;
  }

  async remove(id: string, ctx: TenantContext) {
    await this.findOne(id, ctx);

    await this.audit.log({
      action: 'accesorio.delete',
      entityType: 'Accesorio',
      entityId: id,
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      payload: {},
    });

    return this.prisma.accesorio.update({
      where: { id },
      data: { isActive: false },
      select: { id: true, nombre: true, isActive: true },
    });
  }
}
