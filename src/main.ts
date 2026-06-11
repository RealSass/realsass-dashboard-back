// src/main.ts
import { NestFactory }            from '@nestjs/core';
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

  app.use(cookieParser());
  app.setGlobalPrefix('api/v1');

  const rawOrigins = config.get<string>('ALLOWED_ORIGINS', '');
  const allowedOrigins = rawOrigins
    .split(',')
    .map(o => o.trim())
    .filter(Boolean);

  app.enableCors({
    origin:         allowedOrigins.length > 0 ? allowedOrigins : true,
    methods:        ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-organization-id'],
    credentials:    true,
  });

  app.useGlobalPipes(new ValidationPipe({
    whitelist:            true,
    forbidNonWhitelisted: true,
    transform:            true,
    transformOptions:     { enableImplicitConversion: true },
  }));

  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalInterceptors(new ResponseInterceptor());

  const swaggerConfig = new DocumentBuilder()
    .setTitle('Dashboard API')
    .setVersion('1.0')
    .addBearerAuth({ type: 'http', scheme: 'bearer', bearerFormat: 'JWT' }, 'firebase-jwt')
    .build();
  SwaggerModule.setup('api/v1/docs', app, SwaggerModule.createDocument(app, swaggerConfig));

  const port = config.get<number>('PORT', 3000);
  await app.listen(port);

  logger.log(`🚀 Dashboard API en: http://localhost:${port}`);
  logger.log(`🔥 Firebase Auth SSO activo`);
  logger.log(`📡 Prefix: /api/v1`);
  logger.log(`🍪 Cookies habilitadas`);
}

bootstrap();
