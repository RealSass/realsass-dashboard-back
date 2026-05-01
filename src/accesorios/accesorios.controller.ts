// src/accesorios/accesorios.controller.ts
import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AccesoriosService } from './accesorios.service';
import { CreateAccesorioDto } from './dto/create-accesorio.dto';
import { UpdateAccesorioDto } from './dto/update-accesorio.dto';
import { TenantGuard } from '../tenant/tenant.guard';
import { TenantCtx } from '../tenant/tenant.decorator';
import type { TenantContext } from '../tenant/tenant.interface';

@UseGuards(TenantGuard)
@Controller('api/v1/accesorios')
export class AccesoriosController {
  constructor(private readonly accesoriosService: AccesoriosService) {}

  @Post()
  create(
    @Body() dto: CreateAccesorioDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.accesoriosService.create(dto, ctx);
  }

  @Get()
  findAll(
    @TenantCtx() ctx: TenantContext,
    @Query('nombre') nombre?: string,
    @Query('tipo') tipo?: string,
    @Query('puntoDeVentaId') puntoDeVentaId?: string,
  ) {
    return this.accesoriosService.findAll(ctx, { nombre, tipo, puntoDeVentaId });
  }

  @Get(':id')
  findOne(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.accesoriosService.findOne(id, ctx);
  }

  @Patch(':id')
  update(
    @Param('id') id: string,
    @Body() dto: UpdateAccesorioDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.accesoriosService.update(id, dto, ctx);
  }

  @Delete(':id')
  remove(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.accesoriosService.remove(id, ctx);
  }
}
