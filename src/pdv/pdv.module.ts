// src/pdv/pdv.module.ts
import { Module } from '@nestjs/common';
import { PuntoDeVentaController } from './pdv.controller';
import { PuntoDeVentaService } from './pdv.service';
import { TenantModule } from '../tenant/tenant.module';

@Module({
  imports: [TenantModule],
  controllers: [PuntoDeVentaController],
  providers: [PuntoDeVentaService],
})
export class PdvModule {}
