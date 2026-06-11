#!/usr/bin/env bash
# =============================================================================
# fix-cookies-dashboard-back.sh
# Repo: real-dashboard-back (NestJS)
#
# CAMBIO: POST /auth/firebase-sso además de devolver los tokens en el body,
# los escribe como cookies HttpOnly para que el browser las envíe
# automáticamente al dashboard-front cross-domain.
#
# COOKIES EMITIDAS:
#   access_token  → JWT 15min  — HttpOnly, Secure, SameSite=None
#   refresh_token → JWT 7d     — HttpOnly, Secure, SameSite=None, Path=/api/v1/auth/refresh
#
# SameSite=None; Secure es requerido para cross-domain (subdominios distintos).
# El body sigue devolviendo los tokens para compatibilidad con código existente.
#
# ARCHIVOS MODIFICADOS:
#   src/auth/auth.controller.ts  — setea las cookies en la response
#   src/main.ts                  — habilita credentials en CORS
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
step() { echo -e "\n${YELLOW}▶${NC} $1"; }

[ -f "package.json" ] || { echo "Ejecutá desde el root de real-dashboard-back"; exit 1; }
[ -f "src/auth/auth.controller.ts" ] || { echo "No encontré src/auth/auth.controller.ts"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. src/auth/auth.controller.ts
# ─────────────────────────────────────────────────────────────────────────────
step "Reescribiendo src/auth/auth.controller.ts"

cat > src/auth/auth.controller.ts << 'EOF'
// src/auth/auth.controller.ts
import {
  Controller,
  Post,
  Get,
  Body,
  Req,
  Res,
  HttpCode,
  HttpStatus,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
} from '@nestjs/swagger';
import { AuthService }        from './auth.service';
import { FirebaseAuthGuard }  from './guards/firebase-auth.guard';
import { FirebaseSsoDto }     from './dto/firebase-sso.dto';
import { SyncAuthDto }        from './dto/sync-auth.dto';
import { RefreshTokenDto }    from './dto/refresh-token.dto';
import { Public }             from '../common/decorators/public.decorator';
import { CurrentUser }        from '../common/decorators/current-user.decorator';

// ─── Helpers de cookie ────────────────────────────────────────────────────────

const IS_PROD = process.env.NODE_ENV === 'production';

/**
 * Escribe access_token y refresh_token como cookies HttpOnly.
 * SameSite=None; Secure es requerido para cross-domain (Railway subdominios).
 */
function setAuthCookies(res: Response, accessToken: string, refreshToken: string): void {
  const base = {
    httpOnly: true,
    secure:   IS_PROD,           // solo HTTPS en producción
    sameSite: IS_PROD            // cross-domain en prod, lax en dev
      ? ('none' as const)
      : ('lax'  as const),
    path: '/',
  };

  res.cookie('access_token', accessToken, {
    ...base,
    maxAge: 15 * 60 * 1000,      // 15 minutos
  });

  res.cookie('refresh_token', refreshToken, {
    ...base,
    maxAge: 7 * 24 * 60 * 60 * 1000,  // 7 días
    path:   '/api/v1/auth/refresh',    // solo accesible en el endpoint de refresh
  });
}

function clearAuthCookies(res: Response): void {
  const opts = {
    httpOnly: true,
    secure:   IS_PROD,
    sameSite: IS_PROD ? ('none' as const) : ('lax' as const),
  };
  res.clearCookie('access_token',  { ...opts, path: '/' });
  res.clearCookie('refresh_token', { ...opts, path: '/api/v1/auth/refresh' });
}

// ─── Controller ───────────────────────────────────────────────────────────────

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /**
   * POST /api/v1/auth/firebase-sso
   * Intercambia un Firebase ID Token por JWT propio del dashboard.
   * Escribe los tokens como cookies HttpOnly (cross-domain) Y los devuelve
   * en el body para compatibilidad con clientes que usan localStorage.
   */
  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'SSO con Firebase ID Token → JWT propio' })
  @ApiResponse({ status: 200, description: 'Login exitoso' })
  @ApiResponse({ status: 401, description: 'Token Firebase inválido' })
  async firebaseSso(
    @Body() dto: FirebaseSsoDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result = await this.authService.firebaseSso(dto);
    // Escribir cookies HttpOnly para el browser
    setAuthCookies(res, result.accessToken, result.refreshToken);
    // Devolver también en body (compatibilidad con código que lee localStorage)
    return result;
  }

  /**
   * POST /api/v1/auth/sync
   * Crea o actualiza el usuario en la DB del dashboard.
   * Requiere Firebase token en Authorization header.
   */
  @UseGuards(FirebaseAuthGuard)
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  @ApiBearerAuth('firebase-jwt')
  @ApiOperation({ summary: 'Sincronizar usuario con Firebase' })
  async sync(
    @Body() dto: SyncAuthDto,
    @CurrentUser() currentUser: { uid: string; email: string },
  ) {
    return this.authService.sync({
      ...dto,
      firebaseUid: currentUser.uid,
      email:       dto.email || currentUser.email,
    });
  }

  /**
   * GET /api/v1/auth/me
   * Retorna el perfil del usuario autenticado.
   * Acepta JWT en Authorization header O en cookie access_token.
   */
  @UseGuards(FirebaseAuthGuard)
  @Get('me')
  @ApiBearerAuth('firebase-jwt')
  @ApiOperation({ summary: 'Perfil del usuario autenticado' })
  async me(@CurrentUser() currentUser: { uid: string }) {
    return this.authService.me(currentUser.uid);
  }

  /**
   * POST /api/v1/auth/refresh
   * Renueva el access token usando el refresh token.
   * Lee el refresh_token de la cookie O del body.
   */
  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Renovar access token' })
  async refresh(
    @Body() dto: RefreshTokenDto,
    @Req()  req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    // Preferir cookie sobre body
    const refreshToken = (req.cookies?.['refresh_token'] as string | undefined)
      ?? dto.refreshToken;

    const result = await this.authService.refresh({ refreshToken });
    setAuthCookies(res, result.accessToken, result.refreshToken);
    return result;
  }

  /**
   * POST /api/v1/auth/logout
   * Limpia las cookies de auth.
   */
  @Public()
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Cerrar sesión' })
  logout(@Res({ passthrough: true }) res: Response) {
    clearAuthCookies(res);
    return { success: true, message: 'Sesión cerrada' };
  }
}
EOF
ok "src/auth/auth.controller.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 2. src/auth/guards/firebase-auth.guard.ts
#    Leer JWT de cookie access_token además de Authorization header
# ─────────────────────────────────────────────────────────────────────────────
step "Actualizando src/auth/guards/firebase-auth.guard.ts"

cat > src/auth/guards/firebase-auth.guard.ts << 'EOF'
// src/auth/guards/firebase-auth.guard.ts
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Inject,
  Logger,
} from '@nestjs/common';
import { Reflector }    from '@nestjs/core';
import type { Request } from 'express';
import type * as admin  from 'firebase-admin';
import { FIREBASE_ADMIN } from '../../firebase/firebase.module';
import { IS_PUBLIC_KEY }  from '../guards/firebase-auth.guard';

export { IS_PUBLIC_KEY };

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  private readonly logger = new Logger(FirebaseAuthGuard.name);

  constructor(
    @Inject(FIREBASE_ADMIN) private readonly firebase: admin.app.App | null,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const token   = this.extractToken(request);

    if (!token) throw new UnauthorizedException('Token de autenticación requerido');
    if (!this.firebase) throw new UnauthorizedException('Firebase no configurado');

    try {
      const decoded = await this.firebase.auth().verifyIdToken(token, true);
      (request as any).firebaseUser = decoded;
      (request as any).user = {
        uid:         decoded.uid,
        email:       decoded.email ?? '',
        firebaseUid: decoded.uid,
      };
      return true;
    } catch (err) {
      this.logger.warn(`Token inválido: ${(err as Error).message}`);
      throw new UnauthorizedException('Token inválido o expirado');
    }
  }

  private extractToken(request: Request): string | null {
    // 1. Authorization: Bearer <token>
    const [type, token] = request.headers.authorization?.split(' ') ?? [];
    if (type === 'Bearer' && token) return token;

    // 2. Cookie access_token (para requests cross-domain con credentials)
    const cookie = request.cookies?.['access_token'] as string | undefined;
    if (cookie) return cookie;

    return null;
  }
}
EOF
ok "src/auth/guards/firebase-auth.guard.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 3. src/main.ts — habilitar cookies en CORS
# ─────────────────────────────────────────────────────────────────────────────
step "Actualizando src/main.ts para habilitar credentials en CORS"

# Verificar que existe main.ts
[ -f "src/main.ts" ] || { echo "No encontré src/main.ts"; exit 1; }

# Backup
cp src/main.ts src/main.ts.bak

# Reemplazar la config de CORS — buscar el bloque enableCors y actualizarlo
cat > src/main.ts << 'EOF'
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
EOF
ok "src/main.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Instalar cookie-parser
# ─────────────────────────────────────────────────────────────────────────────
step "Instalando cookie-parser"
pnpm add cookie-parser
pnpm add -D @types/cookie-parser
ok "cookie-parser instalado"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Script completado${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Archivos modificados:"
echo "    • src/auth/auth.controller.ts       (cookies en firebase-sso y refresh)"
echo "    • src/auth/guards/firebase-auth.guard.ts (lee cookie además de header)"
echo "    • src/main.ts                       (cookie-parser + CORS credentials)"
echo ""
echo "  Variable requerida en Railway del dashboard-back:"
echo "    ALLOWED_ORIGINS=https://realsass-dashboard-front-production.up.railway.app,https://realsass-sass-front-production.up.railway.app"
echo ""