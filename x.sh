#!/usr/bin/env bash
# =============================================================================
# fix-main-prefix.sh
# Agrega setGlobalPrefix('api/v1') al main.ts del dashboard-back
# USO: cd <raiz-de-dashboard-back> && bash fix-main-prefix.sh
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓  $*${NC}"; }
step() { echo -e "\n${BLUE}── $* ──────────────────────────────${NC}"; }

step "src/main.ts — agregando globalPrefix api/v1"

cat > src/main.ts << 'EOF'
// src/main.ts
import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { LoggingMiddleware } from './common/middleware/logging.middleware';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  // Prefijo global — todos los endpoints quedan bajo /api/v1/...
  app.setGlobalPrefix('api/v1');

  // CORS
  app.enableCors({
    origin: '*',
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'x-organization-id',
    ],
    credentials: false,
  });

  // Global pipes
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist:              true,
      forbidNonWhitelisted:   true,
      transform:              true,
      transformOptions:       { enableImplicitConversion: true },
    }),
  );

  // Global filters
  app.useGlobalFilters(new HttpExceptionFilter());

  // Global interceptors
  app.useGlobalInterceptors(new ResponseInterceptor());

  const port = configService.get<number>('PORT', 3000);
  await app.listen(port);

  logger.log(`🚀 Dashboard API corriendo en: http://localhost:${port}`);
  logger.log(`🔥 Firebase Auth SSO activo`);
  logger.log(`📡 Prefix: /api/v1`);
}

bootstrap();
EOF

ok "src/main.ts — setGlobalPrefix('api/v1') agregado"

echo ""
echo -e "${GREEN}══ listo ═════════════════════════════════════════════════════${NC}"
echo "  Todos los endpoints ahora responden bajo /api/v1/"
echo "  Ejemplos:"
echo "    POST /api/v1/auth/firebase-sso"
echo "    POST /api/v1/auth/sync"
echo "    GET  /api/v1/auth/me"
echo ""
echo "  Variable en Railway (real-front):"
echo "    NEXT_PUBLIC_DASHBOARD_API_URL=https://tu-dashboard-back.railway.app/api/v1"
echo ""
echo "  → pnpm run build && pnpm start:prod"
echo ""