// src/propiedades/propiedades.service.ts
import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreatePropiedadDto } from './dto/create-propiedad.dto';
import { UpdatePropiedadDto } from './dto/update-propiedad.dto';
import { FilterPropiedadDto } from './dto/filter-propiedad.dto';
import type { TenantContext } from '../tenant/tenant.interface';
import { Prisma } from '@prisma/client';

@Injectable()
export class PropiedadesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(dto: CreatePropiedadDto, ctx: TenantContext) {
    // Validar que la zona pertenece a la org si se provee
    if (dto.zonaId) {
      const zona = await this.prisma.zona.findFirst({
        where: { id: dto.zonaId, organizationId: ctx.organizationId, isActive: true },
      });
      if (!zona) {
        throw new BadRequestException('La zona especificada no existe o no pertenece a esta organización');
      }
    }

    const propiedad = await this.prisma.propiedad.create({
      data: {
        titulo:         dto.titulo,
        descripcion:    dto.descripcion,
        tipo:           dto.tipo,
        operacion:      dto.operacion,
        precio:         dto.precio,
        moneda:         dto.moneda ?? 'USD',
        superficie:     dto.superficie,
        ambientes:      dto.ambientes,
        banos:          dto.banos,
        dormitorios:    dto.dormitorios,
        direccion:      dto.direccion,
        estado:         dto.estado ?? 'DISPONIBLE',
        destacada:      dto.destacada ?? false,
        organizationId: ctx.organizationId,
        zonaId:         dto.zonaId,
        imagenes: dto.imagenes
          ? {
              create: dto.imagenes.map((url, orden) => ({ url, orden })),
            }
          : undefined,
      },
      include: {
        imagenes: { orderBy: { orden: 'asc' } },
        zona:     { select: { id: true, nombre: true } },
      },
    });

    await this.audit.log({
      action:         'propiedad.create',
      entityType:     'Propiedad',
      entityId:       propiedad.id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        { titulo: dto.titulo, tipo: dto.tipo, operacion: dto.operacion },
    });

    return { success: true, data: propiedad };
  }

  async findAll(filters: FilterPropiedadDto, ctx: TenantContext) {
    const page  = filters.page  ?? 1;
    const limit = Math.min(filters.limit ?? 20, 100); // máx 100 por página
    const skip  = (page - 1) * limit;

    const where: Prisma.PropiedadWhereInput = {
      organizationId: ctx.organizationId,
      isActive:       true,
      ...(filters.tipo      && { tipo:      filters.tipo      }),
      ...(filters.operacion && { operacion: filters.operacion }),
      ...(filters.estado    && { estado:    filters.estado    }),
      ...(filters.zonaId    && { zonaId:    filters.zonaId    }),
      ...(filters.buscar && {
        OR: [
          { titulo:     { contains: filters.buscar, mode: 'insensitive' } },
          { descripcion:{ contains: filters.buscar, mode: 'insensitive' } },
          { direccion:  { contains: filters.buscar, mode: 'insensitive' } },
        ],
      }),
      ...((filters.precioMin != null || filters.precioMax != null) && {
        precio: {
          ...(filters.precioMin != null && { gte: filters.precioMin }),
          ...(filters.precioMax != null && { lte: filters.precioMax }),
        },
      }),
    };

    const [total, items] = await Promise.all([
      this.prisma.propiedad.count({ where }),
      this.prisma.propiedad.findMany({
        where,
        include: {
          imagenes: { orderBy: { orden: 'asc' }, take: 1 },
          zona:     { select: { id: true, nombre: true } },
        },
        orderBy: [
          { destacada: 'desc' },
          { createdAt: 'desc' },
        ],
        skip,
        take: limit,
      }),
    ]);

    return {
      success: true,
      data: items,
      meta: {
        total,
        page,
        limit,
        totalPages:  Math.ceil(total / limit),
        hasPrevPage: page > 1,
        hasNextPage: page < Math.ceil(total / limit),
      },
    };
  }

  async findOne(id: string, ctx: TenantContext) {
    const propiedad = await this.prisma.propiedad.findFirst({
      where: { id, organizationId: ctx.organizationId, isActive: true },
      include: {
        imagenes: { orderBy: { orden: 'asc' } },
        zona:     { select: { id: true, nombre: true, ciudad: true } },
      },
    });

    if (!propiedad) throw new NotFoundException('Propiedad no encontrada');
    return { success: true, data: propiedad };
  }

  async update(id: string, dto: UpdatePropiedadDto, ctx: TenantContext) {
    await this.findOne(id, ctx); // verifica que existe y pertenece a la org

    if (dto.zonaId) {
      const zona = await this.prisma.zona.findFirst({
        where: { id: dto.zonaId, organizationId: ctx.organizationId, isActive: true },
      });
      if (!zona) throw new BadRequestException('Zona inválida');
    }

    const propiedad = await this.prisma.propiedad.update({
      where: { id },
      data: {
        ...(dto.titulo       != null && { titulo:       dto.titulo       }),
        ...(dto.descripcion  != null && { descripcion:  dto.descripcion  }),
        ...(dto.tipo         != null && { tipo:         dto.tipo         }),
        ...(dto.operacion    != null && { operacion:    dto.operacion    }),
        ...(dto.precio       != null && { precio:       dto.precio       }),
        ...(dto.moneda       != null && { moneda:       dto.moneda       }),
        ...(dto.superficie   != null && { superficie:   dto.superficie   }),
        ...(dto.ambientes    != null && { ambientes:    dto.ambientes    }),
        ...(dto.banos        != null && { banos:        dto.banos        }),
        ...(dto.dormitorios  != null && { dormitorios:  dto.dormitorios  }),
        ...(dto.direccion    != null && { direccion:    dto.direccion    }),
        ...(dto.estado       != null && { estado:       dto.estado       }),
        ...(dto.destacada    != null && { destacada:    dto.destacada    }),
        ...(dto.zonaId       != null && { zonaId:       dto.zonaId       }),
        ...(dto.imagenes && {
          imagenes: {
            deleteMany: {},
            create: dto.imagenes.map((url, orden) => ({ url, orden })),
          },
        }),
      },
      include: {
        imagenes: { orderBy: { orden: 'asc' } },
        zona:     { select: { id: true, nombre: true } },
      },
    });

    await this.audit.log({
      action:         'propiedad.update',
      entityType:     'Propiedad',
      entityId:       id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        dto as Record<string, unknown>,
    });

    return { success: true, data: propiedad };
  }

  async remove(id: string, ctx: TenantContext) {
    await this.findOne(id, ctx);

    await this.prisma.propiedad.update({
      where: { id },
      data: { isActive: false },
    });

    await this.audit.log({
      action:         'propiedad.delete',
      entityType:     'Propiedad',
      entityId:       id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        {},
    });

    return { success: true, message: 'Propiedad eliminada correctamente' };
  }
}
