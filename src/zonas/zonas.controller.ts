// src/zonas/zonas.controller.ts
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
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { ZonasService } from './zonas.service';
import { CreateZonaDto } from './dto/create-zona.dto';
import { UpdateZonaDto } from './dto/update-zona.dto';
import { TenantGuard } from '../tenant/tenant.guard';
import { TenantCtx } from '../tenant/tenant.decorator';
import type { TenantContext } from '../tenant/tenant.interface';

@ApiTags('zonas')
@ApiBearerAuth('firebase-jwt')
@UseGuards(TenantGuard)
@Controller('api/v1/zonas')
export class ZonasController {
  constructor(private readonly zonasService: ZonasService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Crear zona' })
  @ApiResponse({ status: 201, description: 'Zona creada' })
  create(@Body() dto: CreateZonaDto, @TenantCtx() ctx: TenantContext) {
    return this.zonasService.create(dto, ctx);
  }

  @Get()
  @ApiOperation({ summary: 'Listar todas las zonas activas de la org' })
  findAll(@TenantCtx() ctx: TenantContext) {
    return this.zonasService.findAll(ctx);
  }

  @Get(':id')
  @ApiParam({ name: 'id', description: 'ID de la zona' })
  @ApiOperation({ summary: 'Obtener una zona por ID' })
  findOne(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.zonasService.findOne(id, ctx);
  }

  @Patch(':id')
  @ApiParam({ name: 'id', description: 'ID de la zona' })
  @ApiOperation({ summary: 'Actualizar zona' })
  update(
    @Param('id') id: string,
    @Body() dto: UpdateZonaDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.zonasService.update(id, dto, ctx);
  }

  @Delete(':id')
  @ApiParam({ name: 'id', description: 'ID de la zona' })
  @ApiOperation({ summary: 'Desactivar zona (soft delete)' })
  @ApiResponse({ status: 200, description: 'Zona eliminada' })
  @ApiResponse({ status: 409, description: 'La zona tiene propiedades activas' })
  remove(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.zonasService.remove(id, ctx);
  }
}
