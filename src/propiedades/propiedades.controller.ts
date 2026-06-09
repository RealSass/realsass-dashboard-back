// src/propiedades/propiedades.controller.ts
import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { PropiedadesService } from './propiedades.service';
import { CreatePropiedadDto } from './dto/create-propiedad.dto';
import { UpdatePropiedadDto } from './dto/update-propiedad.dto';
import { FilterPropiedadDto } from './dto/filter-propiedad.dto';
import { TenantGuard } from '../tenant/tenant.guard';
import { TenantCtx } from '../tenant/tenant.decorator';
import type { TenantContext } from '../tenant/tenant.interface';

@ApiTags('propiedades')
@ApiBearerAuth('firebase-jwt')
@UseGuards(TenantGuard)
@Controller('propiedades')
export class PropiedadesController {
  constructor(private readonly propiedadesService: PropiedadesService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Crear propiedad' })
  create(@Body() dto: CreatePropiedadDto, @TenantCtx() ctx: TenantContext) {
    return this.propiedadesService.create(dto, ctx);
  }

  @Get()
  @ApiOperation({ summary: 'Listar propiedades con filtros y paginación' })
  findAll(
    @Query() filters: FilterPropiedadDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.propiedadesService.findAll(filters, ctx);
  }

  @Get(':id')
  @ApiParam({ name: 'id', description: 'ID de la propiedad' })
  @ApiOperation({ summary: 'Obtener propiedad por ID' })
  findOne(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.propiedadesService.findOne(id, ctx);
  }

  @Patch(':id')
  @ApiParam({ name: 'id', description: 'ID de la propiedad' })
  @ApiOperation({ summary: 'Actualizar propiedad' })
  update(
    @Param('id') id: string,
    @Body() dto: UpdatePropiedadDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.propiedadesService.update(id, dto, ctx);
  }

  @Delete(':id')
  @ApiParam({ name: 'id', description: 'ID de la propiedad' })
  @ApiOperation({ summary: 'Eliminar propiedad (soft delete)' })
  @ApiResponse({ status: 200, description: 'Propiedad eliminada' })
  remove(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.propiedadesService.remove(id, ctx);
  }
}
