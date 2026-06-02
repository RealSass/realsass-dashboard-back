// src/zonas/zonas.service.ts
import {
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreateZonaDto } from './dto/create-zona.dto';
import { UpdateZonaDto } from './dto/update-zona.dto';
import type { TenantContext } from '../tenant/tenant.interface';

@Injectable()
export class ZonasService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(dto: CreateZonaDto, ctx: TenantContext) {
    // Verificar nombre único por organización
    const existing = await this.prisma.zona.findFirst({
      where: {
        organizationId: ctx.organizationId,
        nombre: { equals: dto.nombre, mode: 'insensitive' },
        isActive: true,
      },
    });
    if (existing) {
      throw new ConflictException(`Ya existe una zona con el nombre "${dto.nombre}"`);
    }

    const zona = await this.prisma.zona.create({
      data: {
        nombre:         dto.nombre,
        ciudad:         dto.ciudad,
        provincia:      dto.provincia,
        descripcion:    dto.descripcion,
        organizationId: ctx.organizationId,
      },
    });

    await this.audit.log({
      action:         'zona.create',
      entityType:     'Zona',
      entityId:       zona.id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        { nombre: dto.nombre },
    });

    return { success: true, data: zona };
  }

  async findAll(ctx: TenantContext) {
    const zonas = await this.prisma.zona.findMany({
      where: { organizationId: ctx.organizationId, isActive: true },
      include: {
        _count: { select: { propiedades: { where: { isActive: true } } } },
      },
      orderBy: { nombre: 'asc' },
    });

    return { success: true, data: zonas };
  }

  async findOne(id: string, ctx: TenantContext) {
    const zona = await this.prisma.zona.findFirst({
      where: { id, organizationId: ctx.organizationId, isActive: true },
      include: {
        _count: { select: { propiedades: { where: { isActive: true } } } },
      },
    });

    if (!zona) throw new NotFoundException('Zona no encontrada');
    return { success: true, data: zona };
  }

  async update(id: string, dto: UpdateZonaDto, ctx: TenantContext) {
    await this.findOne(id, ctx);

    if (dto.nombre) {
      const conflict = await this.prisma.zona.findFirst({
        where: {
          organizationId: ctx.organizationId,
          nombre: { equals: dto.nombre, mode: 'insensitive' },
          isActive: true,
          NOT: { id },
        },
      });
      if (conflict) {
        throw new ConflictException(`Ya existe otra zona con el nombre "${dto.nombre}"`);
      }
    }

    const zona = await this.prisma.zona.update({
      where: { id },
      data: {
        ...(dto.nombre      && { nombre:      dto.nombre      }),
        ...(dto.ciudad      && { ciudad:      dto.ciudad      }),
        ...(dto.provincia   && { provincia:   dto.provincia   }),
        ...(dto.descripcion && { descripcion: dto.descripcion }),
      },
    });

    await this.audit.log({
      action:         'zona.update',
      entityType:     'Zona',
      entityId:       id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        dto as Record<string, unknown>,
    });

    return { success: true, data: zona };
  }

  async remove(id: string, ctx: TenantContext) {
    await this.findOne(id, ctx);

    // Verificar que no tenga propiedades activas antes de desactivar
    const propCount = await this.prisma.propiedad.count({
      where: { zonaId: id, isActive: true },
    });

    if (propCount > 0) {
      throw new ConflictException(
        `No se puede eliminar la zona: tiene ${propCount} propiedad(es) activa(s)`,
      );
    }

    await this.prisma.zona.update({
      where: { id },
      data: { isActive: false },
    });

    await this.audit.log({
      action:         'zona.delete',
      entityType:     'Zona',
      entityId:       id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        {},
    });

    return { success: true, message: 'Zona eliminada correctamente' };
  }
}
