// src/main.ts
import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { LoggingMiddleware } from './common/middleware/logging.middleware';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  // Seguridad HTTP
  app.use(helmet());

  // CORS — permite headers del ecosistema SSO
  const allowedOrigins = configService
    .get<string>('ALLOWED_ORIGINS', 'http://localhost:3002')
    .split(',')
    .map((o) => o.trim());

  app.enableCors({
    origin:         allowedOrigins,
    methods:        ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-organization-id'],
    credentials:    true,
  });

  // Pipes
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist:            true,
      forbidNonWhitelisted: true,
      transform:            true,
      transformOptions:     { enableImplicitConversion: true },
    }),
  );

  // Filters e interceptors
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalInterceptors(new ResponseInterceptor());

  // Swagger (solo en non-production)
  if (configService.get('NODE_ENV') !== 'production') {
    const config = new DocumentBuilder()
      .setTitle('Real Estate Dashboard API')
      .setDescription('Sistema 2 — Dashboard de gestión para inmobiliarias')
      .setVersion('1.0')
      .addBearerAuth(
        { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
        'firebase-jwt',
      )
      .build();
    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('api/docs', app, document, {
      swaggerOptions: { persistAuthorization: true },
    });
  }

  const port = configService.get<number>('PORT', 3001);
  await app.listen(port);

  logger.log(`🚀 Real Estate Dashboard API: http://localhost:${port}`);
  logger.log(`🔥 Firebase Auth SSO activo`);
  logger.log(`🏢 Multi-tenant (x-organization-id)`);
  logger.log(`🔗 Sistema 1 URL: ${configService.get('REAL_BACK_URL')}`);
  if (configService.get('NODE_ENV') !== 'production') {
    logger.log(`📄 Swagger docs: http://localhost:${port}/api/docs`);
  }
}

bootstrap();
