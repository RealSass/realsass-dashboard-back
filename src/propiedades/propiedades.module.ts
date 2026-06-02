// src/propiedades/propiedades.module.ts
import { Module } from '@nestjs/common';
import { PropiedadesController } from './propiedades.controller';
import { PropiedadesService } from './propiedades.service';
import { TenantModule } from '../tenant/tenant.module';
import { AuditModule } from '../audit/audit.module';

@Module({
  imports: [TenantModule, AuditModule],
  controllers: [PropiedadesController],
  providers: [PropiedadesService],
  exports: [PropiedadesService],
})
export class PropiedadesModule {}
