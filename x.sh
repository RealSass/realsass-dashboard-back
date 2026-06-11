#!/usr/bin/env bash
# =============================================================================
# fix-cookies-dashboard-back.sh — v2 (fix circular import)
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
step() { echo -e "\n${YELLOW}▶${NC} $1"; }

[ -f "package.json" ] || { echo "Ejecutá desde el root de real-dashboard-back"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. src/auth/guards/firebase-auth.guard.ts — sin circular export
# ─────────────────────────────────────────────────────────────────────────────
step "Reescribiendo src/auth/guards/firebase-auth.guard.ts"
mkdir -p src/auth/guards

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

export const IS_PUBLIC_KEY = 'isPublic';

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

    // 2. Cookie access_token (cross-domain con credentials:include)
    const cookie = (request.cookies as Record<string, string> | undefined)?.['access_token'];
    if (cookie) return cookie;

    return null;
  }
}
EOF
ok "src/auth/guards/firebase-auth.guard.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 2. src/common/decorators/public.decorator.ts — usa IS_PUBLIC_KEY del guard
# ─────────────────────────────────────────────────────────────────────────────
step "Actualizando src/common/decorators/public.decorator.ts"
mkdir -p src/common/decorators

cat > src/common/decorators/public.decorator.ts << 'EOF'
// src/common/decorators/public.decorator.ts
import { SetMetadata } from '@nestjs/common';
import { IS_PUBLIC_KEY } from '../../auth/guards/firebase-auth.guard';

export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
EOF
ok "src/common/decorators/public.decorator.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 3. src/auth/auth.controller.ts
# ─────────────────────────────────────────────────────────────────────────────
step "Reescribiendo src/auth/auth.controller.ts"
mkdir -p src/auth

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
import { AuthService }       from './auth.service';
import { FirebaseAuthGuard } from './guards/firebase-auth.guard';
import { FirebaseSsoDto }    from './dto/firebase-sso.dto';
import { SyncAuthDto }       from './dto/sync-auth.dto';
import { RefreshTokenDto }   from './dto/refresh-token.dto';
import { Public }            from '../common/decorators/public.decorator';
import { CurrentUser }       from '../common/decorators/current-user.decorator';

const IS_PROD = process.env.NODE_ENV === 'production';

function setAuthCookies(res: Response, accessToken: string, refreshToken: string): void {
  const base = {
    httpOnly: true,
    secure:   IS_PROD,
    sameSite: IS_PROD ? ('none' as const) : ('lax' as const),
  };

  res.cookie('access_token', accessToken, {
    ...base,
    path:   '/',
    maxAge: 15 * 60 * 1000,
  });

  res.cookie('refresh_token', refreshToken, {
    ...base,
    path:   '/api/v1/auth/refresh',
    maxAge: 7 * 24 * 60 * 60 * 1000,
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

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'SSO con Firebase ID Token → JWT + cookies' })
  @ApiResponse({ status: 200, description: 'Login exitoso' })
  async firebaseSso(
    @Body() dto: FirebaseSsoDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result = await this.authService.firebaseSso(dto);
    setAuthCookies(res, result.accessToken, result.refreshToken);
    return result;
  }

  @UseGuards(FirebaseAuthGuard)
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  @ApiBearerAuth('firebase-jwt')
  @ApiOperation({ summary: 'Sincronizar usuario con Firebase' })
  async sync(
    @Body() dto: SyncAuthDto,
    @CurrentUser() cu: { uid: string; email: string },
  ) {
    return this.authService.sync({ ...dto, firebaseUid: cu.uid, email: dto.email || cu.email });
  }

  @UseGuards(FirebaseAuthGuard)
  @Get('me')
  @ApiBearerAuth('firebase-jwt')
  @ApiOperation({ summary: 'Perfil del usuario autenticado' })
  async me(@CurrentUser() cu: { uid: string }) {
    return this.authService.me(cu.uid);
  }

  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Renovar access token' })
  async refresh(
    @Body() dto: RefreshTokenDto,
    @Req()  req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const refreshToken =
      (req.cookies as Record<string, string> | undefined)?.['refresh_token']
      ?? dto.refreshToken;

    const result = await this.authService.refresh({ refreshToken });
    setAuthCookies(res, result.accessToken, result.refreshToken);
    return result;
  }

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
# 4. src/main.ts
# ─────────────────────────────────────────────────────────────────────────────
step "Reescribiendo src/main.ts"

cat > src/main.ts << 'EOF'
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
EOF
ok "src/main.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 5. Instalar cookie-parser
# ─────────────────────────────────────────────────────────────────────────────
step "Instalando cookie-parser"
pnpm add cookie-parser
pnpm add -D @types/cookie-parser
ok "cookie-parser instalado"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Completado. Agregar en Railway dashboard-back:${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo "  ALLOWED_ORIGINS=https://realsass-dashboard-front-production.up.railway.app,https://realsass-sass-front-production.up.railway.app"
echo ""