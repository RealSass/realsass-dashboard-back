// src/app.module.ts
import { Module, MiddlewareConsumer, NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from './prisma/prisma.module';
import { FirebaseModule } from './firebase/firebase.module';
import { TenantModule } from './tenant/tenant.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { ZonasModule } from './zonas/zonas.module';
import { PropiedadesModule } from './propiedades/propiedades.module';
import { HealthModule } from './health/health.module';
import { LoggingMiddleware } from './common/middleware/logging.middleware';
import { envValidation } from './config/env.validation';
import { FirebaseAuthGuard } from './auth/guards/firebase-auth.guard';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal:    true,
      validate:    envValidation,
      envFilePath: '.env',
    }),
    PrismaModule,
    FirebaseModule,
    TenantModule,
    AuthModule,
    UsersModule,
    ZonasModule,
    PropiedadesModule,
    HealthModule,
  ],
  providers: [
    {
      provide:   APP_GUARD,
      useClass:  FirebaseAuthGuard,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggingMiddleware).forRoutes('*');
  }
}
