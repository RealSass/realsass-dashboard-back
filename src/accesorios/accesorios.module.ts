// src/accesorios/accesorios.module.ts
import { Module } from '@nestjs/common';
import { AccesoriosController } from './accesorios.controller';
import { AccesoriosService } from './accesorios.service';
import { TenantModule } from '../tenant/tenant.module';

@Module({
  imports: [TenantModule],
  controllers: [AccesoriosController],
  providers: [AccesoriosService],
  exports: [AccesoriosService],
})
export class AccesoriosModule {}
