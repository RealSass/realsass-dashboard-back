// src/pdv/pdv.controller.ts
import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { PuntoDeVentaService } from './pdv.service';
import { CreatePuntoDeVentaDto } from './dto/create-pdv.dto';
import { UpdatePuntoDeVentaDto } from './dto/update-pdv.dto';
import { TenantGuard } from '../tenant/tenant.guard';
import { TenantCtx } from '../tenant/tenant.decorator';
import type { TenantContext } from '../tenant/tenant.interface';

@UseGuards(TenantGuard)
@Controller('api/v1/pdv')
export class PuntoDeVentaController {
  constructor(private readonly puntoDeVentaService: PuntoDeVentaService) {}

  @Post()
  create(
    @Body() dto: CreatePuntoDeVentaDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.puntoDeVentaService.create(dto, ctx);
  }

  @Get()
  findAll(@TenantCtx() ctx: TenantContext) {
    return this.puntoDeVentaService.findAll(ctx);
  }

  @Get(':id')
  findOne(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.puntoDeVentaService.findOne(id, ctx);
  }

  @Patch(':id')
  update(
    @Param('id') id: string,
    @Body() dto: UpdatePuntoDeVentaDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.puntoDeVentaService.update(id, dto, ctx);
  }

  @Delete(':id')
  remove(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.puntoDeVentaService.remove(id, ctx);
  }
}
