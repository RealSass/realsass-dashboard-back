// src/main.ts
import { NestFactory }           from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { ConfigService }          from '@nestjs/config';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import * as cookieParser          from 'cookie-parser';
import { AppModule }              from './app.module';
import { HttpExceptionFilter }    from './common/filters/http-exception.filter';
import { ResponseInterceptor }    from './common/interceptors/response.interceptor';

async function bootstrap() {
  const app    = await NestFactory.create(AppModule);
  const config = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  // ── Cookie parser (necesario para leer req.cookies) ───────────────────────
  app.use(cookieParser());

  // ── Prefijo global ────────────────────────────────────────────────────────
  app.setGlobalPrefix('api/v1');

  // ── CORS — credentials=true para que el browser envíe cookies cross-domain
  const allowedOrigins = (config.get<string>('ALLOWED_ORIGINS', '') || '')
    .split(',')
    .map(o => o.trim())
    .filter(Boolean);

  app.enableCors({
    origin: allowedOrigins.length > 0
      ? allowedOrigins
      : true,               // en dev sin config, permitir todo
    methods:          ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders:   ['Content-Type', 'Authorization', 'x-organization-id'],
    credentials:      true, // ← REQUERIDO para que el browser envíe cookies
  });

  // ── Pipes ─────────────────────────────────────────────────────────────────
  app.useGlobalPipes(new ValidationPipe({
    whitelist:            true,
    forbidNonWhitelisted: true,
    transform:            true,
    transformOptions:     { enableImplicitConversion: true },
  }));

  // ── Filters & interceptors ────────────────────────────────────────────────
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalInterceptors(new ResponseInterceptor());

  // ── Swagger ───────────────────────────────────────────────────────────────
  const swaggerConfig = new DocumentBuilder()
    .setTitle('Dashboard API')
    .setDescription('Real Estate Dashboard — API docs')
    .setVersion('1.0')
    .addBearerAuth({ type: 'http', scheme: 'bearer', bearerFormat: 'JWT' }, 'firebase-jwt')
    .build();

  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/v1/docs', app, document);

  const port = config.get<number>('PORT', 3000);
  await app.listen(port);

  logger.log(`🚀 Dashboard API corriendo en: http://localhost:${port}`);
  logger.log(`🔥 Firebase Auth SSO activo`);
  logger.log(`📡 Prefix: /api/v1`);
  logger.log(`🍪 Cookie-based auth habilitado`);
}

bootstrap();
