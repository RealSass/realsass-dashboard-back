// src/app.module.ts
import { Module, MiddlewareConsumer, NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from './prisma/prisma.module';
import { FirebaseModule } from './firebase/firebase.module';
import { AuditModule } from './audit/audit.module';
import { TenantModule } from './tenant/tenant.module';
import { AuthModule } from './auth/auth.module';
import { AccesoriosModule } from './accesorios/accesorios.module';
import { SubAccesoriosModule } from './sub-accesorios/sub-accesorios.module';
import { PdvModule } from './pdv/pdv.module';
import { LoggingMiddleware } from './common/middleware/logging.middleware';
import { envValidation } from './config/env.validation';
import { FirebaseAuthGuard } from './auth/guards/firebase-auth.guard';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate: envValidation,
      envFilePath: '.env',
    }),
    PrismaModule,
    FirebaseModule,
    AuditModule,
    TenantModule,
    AuthModule,
    AccesoriosModule,
    SubAccesoriosModule,
    PdvModule,
  ],
  providers: [
    // FirebaseAuthGuard aplicado globalmente — rutas con @Public() se saltan
    {
      provide: APP_GUARD,
      useClass: FirebaseAuthGuard,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggingMiddleware).forRoutes('*');
  }
}
