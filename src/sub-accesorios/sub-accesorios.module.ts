// src/sub-accesorios/sub-accesorios.module.ts
import { Module } from '@nestjs/common';
import { SubAccesoriosController } from './sub-accesorios.controller';
import { SubAccesoriosService } from './sub-accesorios.service';
import { TenantModule } from '../tenant/tenant.module';

@Module({
  imports: [TenantModule],
  controllers: [SubAccesoriosController],
  providers: [SubAccesoriosService],
  exports: [SubAccesoriosService],
})
export class SubAccesoriosModule {}
