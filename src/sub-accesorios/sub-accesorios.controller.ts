// src/sub-accesorios/sub-accesorios.controller.ts
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
import { SubAccesoriosService } from './sub-accesorios.service';
import { CreateSubAccesorioDto } from './dto/create-sub-accesorio.dto';
import { UpdateSubAccesorioDto } from './dto/update-sub-accesorio.dto';
import { TenantGuard } from '../tenant/tenant.guard';
import { TenantCtx } from '../tenant/tenant.decorator';
import type { TenantContext } from '../tenant/tenant.interface';

@UseGuards(TenantGuard)
@Controller('api/v1/sub-accesorios')
export class SubAccesoriosController {
  constructor(private readonly subAccesoriosService: SubAccesoriosService) {}

  @Post()
  create(
    @Body() dto: CreateSubAccesorioDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.subAccesoriosService.create(dto, ctx);
  }

  @Get()
  findAll(
    @TenantCtx() ctx: TenantContext,
    @Query('nombre') nombre?: string,
    @Query('tipo') tipo?: string,
    @Query('puntoDeVentaId') puntoDeVentaId?: string,
  ) {
    return this.subAccesoriosService.findAll(ctx, {
      nombre,
      tipo,
      puntoDeVentaId,
    });
  }

  @Get(':id')
  findOne(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.subAccesoriosService.findOne(id, ctx);
  }

  @Patch(':id')
  update(
    @Param('id') id: string,
    @Body() dto: UpdateSubAccesorioDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.subAccesoriosService.update(id, dto, ctx);
  }

  @Delete(':id')
  remove(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.subAccesoriosService.remove(id, ctx);
  }
}
