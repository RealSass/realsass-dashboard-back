#!/usr/bin/env bash
# =============================================================================
# fix-guard-and-dto.sh — sin Python
# Repo: real-dashboard-back
#
# PROBLEMA: FirebaseAuthGuard verifica la cookie con firebase.verifyIdToken()
# pero la cookie contiene un JWT propio → error "no kid claim"
#
# SOLUCIÓN: cookie → JwtService.verify() / header → firebase.verifyIdToken()
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
step() { echo -e "\n${YELLOW}▶${NC} $1"; }

[ -f "package.json" ] || { echo "Ejecutá desde el root de real-dashboard-back"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. src/auth/guards/firebase-auth.guard.ts
# ─────────────────────────────────────────────────────────────────────────────
step "src/auth/guards/firebase-auth.guard.ts"
mkdir -p src/auth/guards

cat > src/auth/guards/firebase-auth.guard.ts << 'EOF'
// src/auth/guards/firebase-auth.guard.ts
//
// Cookie access_token  → JWT propio  → JwtService.verify()
// Header Authorization → Firebase ID token → firebase.auth().verifyIdToken()
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Inject,
  Logger,
} from '@nestjs/common';
import { Reflector }     from '@nestjs/core';
import { JwtService }    from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import type { Request }  from 'express';
import type * as admin   from 'firebase-admin';
import { FIREBASE_ADMIN } from '../../firebase/firebase.module';

export const IS_PUBLIC_KEY = 'isPublic';

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  private readonly logger = new Logger(FirebaseAuthGuard.name);

  constructor(
    @Inject(FIREBASE_ADMIN) private readonly firebase: admin.app.App | null,
    private readonly reflector: Reflector,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const { token, source } = this.extractToken(request);

    if (!token) throw new UnauthorizedException('Token de autenticación requerido');

    return source === 'cookie'
      ? this.verifyJwt(token, request)
      : this.verifyFirebase(token, request);
  }

  private verifyJwt(token: string, request: Request): boolean {
    try {
      const secret = this.configService.get<string>('JWT_ACCESS_SECRET', 'change_me_access');
      const payload = this.jwtService.verify(token, { secret }) as {
        sub: string; email: string; nombre: string; role: string;
      };
      (request as any).user = {
        uid:         payload.sub,
        email:       payload.email,
        firebaseUid: payload.sub,
        nombre:      payload.nombre,
        role:        payload.role,
      };
      return true;
    } catch (err) {
      this.logger.warn(`JWT inválido: ${(err as Error).message}`);
      throw new UnauthorizedException('Token inválido o expirado');
    }
  }

  private async verifyFirebase(token: string, request: Request): Promise<boolean> {
    if (!this.firebase) throw new UnauthorizedException('Firebase no configurado');
    try {
      const decoded = await this.firebase.auth().verifyIdToken(token, true);
      (request as any).user = {
        uid:         decoded.uid,
        email:       decoded.email ?? '',
        firebaseUid: decoded.uid,
      };
      return true;
    } catch (err) {
      this.logger.warn(`Firebase token inválido: ${(err as Error).message}`);
      throw new UnauthorizedException('Token inválido o expirado');
    }
  }

  private extractToken(request: Request): { token: string | null; source: 'cookie' | 'header' } {
    const cookie = (request.cookies as Record<string, string> | undefined)?.['access_token'];
    if (cookie) return { token: cookie, source: 'cookie' };

    const [type, token] = request.headers.authorization?.split(' ') ?? [];
    if (type === 'Bearer' && token) return { token, source: 'header' };

    return { token: null, source: 'header' };
  }
}
EOF
ok "src/auth/guards/firebase-auth.guard.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 2. src/auth/auth.module.ts
# ─────────────────────────────────────────────────────────────────────────────
step "src/auth/auth.module.ts"

cat > src/auth/auth.module.ts << 'EOF'
// src/auth/auth.module.ts
import { Module }        from '@nestjs/common';
import { JwtModule }     from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { AuthController }  from './auth.controller';
import { AuthService }     from './auth.service';
import { FirebaseAuthGuard } from './guards/firebase-auth.guard';
import { AuditModule }     from '../audit/audit.module';

@Module({
  imports: [
    AuditModule,
    ConfigModule,
    JwtModule.registerAsync({
      imports:    [ConfigModule],
      inject:     [ConfigService],
      useFactory: (cs: ConfigService) => ({
        secret:      cs.get<string>('JWT_ACCESS_SECRET', 'change_me_access'),
        signOptions: {
          expiresIn: cs.get<string>('JWT_ACCESS_EXPIRES_IN', '15m') as any,
        },
      }),
    }),
  ],
  controllers: [AuthController],
  providers:   [AuthService, FirebaseAuthGuard],
  exports:     [AuthService, FirebaseAuthGuard, JwtModule],
})
export class AuthModule {}
EOF
ok "src/auth/auth.module.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 3. src/auth/auth.service.ts — me() busca por id O firebaseUid
#    Reemplazar solo el método me() con sed
# ─────────────────────────────────────────────────────────────────────────────
step "src/auth/auth.service.ts — actualizando me()"

# Escribir el nuevo método en un archivo temporal y usar cat para reemplazar
# el archivo completo leyendo el existente y reemplazando el método me()

# Leer el contenido actual, reemplazar el bloque me() y escribir de vuelta
# Usamos awk para reemplazar entre "async me(" y el cierre del método
awk '
/async me\(firebaseUid: string\)/ { in_me=1; depth=0 }
in_me {
  for(i=1;i<=length($0);i++) {
    c=substr($0,i,1)
    if(c=="{") depth++
    if(c=="}") { depth--; if(depth==0) { in_me=0; print "  async me(uidOrId: string) {\n    const user = await this.prisma.user.findFirst({\n      where: { OR: [{ firebaseUid: uidOrId }, { id: uidOrId }] },\n      select: { id: true, email: true, nombre: true, role: true, firebaseUid: true, isActive: true, createdAt: true },\n    });\n    if (!user) throw new NotFoundException(\"Usuario no encontrado.\");\n    return user;\n  }"; next } }
  }
  next
}
{ print }
' src/auth/auth.service.ts > src/auth/auth.service.ts.tmp \
  && mv src/auth/auth.service.ts.tmp src/auth/auth.service.ts

ok "src/auth/auth.service.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 4. src/auth/dto/refresh-token.dto.ts
# ─────────────────────────────────────────────────────────────────────────────
step "src/auth/dto/refresh-token.dto.ts"

cat > src/auth/dto/refresh-token.dto.ts << 'EOF'
// src/auth/dto/refresh-token.dto.ts
import { IsString, IsOptional } from 'class-validator';

export class RefreshTokenDto {
  // Opcional: viene de cookie HttpOnly O del body como fallback
  @IsString()
  @IsOptional()
  refreshToken?: string;
}
EOF
ok "src/auth/dto/refresh-token.dto.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 5. src/auth/auth.controller.ts
# ─────────────────────────────────────────────────────────────────────────────
step "src/auth/auth.controller.ts"

cat > src/auth/auth.controller.ts << 'EOF'
// src/auth/auth.controller.ts
import {
  Controller, Post, Get, Body,
  Req, Res, HttpCode, HttpStatus, UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { AuthService }       from './auth.service';
import { FirebaseAuthGuard } from './guards/firebase-auth.guard';
import { FirebaseSsoDto }    from './dto/firebase-sso.dto';
import { SyncAuthDto }       from './dto/sync-auth.dto';
import { RefreshTokenDto }   from './dto/refresh-token.dto';
import { Public }            from '../common/decorators/public.decorator';
import { CurrentUser }       from '../common/decorators/current-user.decorator';

const IS_PROD = process.env.NODE_ENV === 'production';

function setAuthCookies(res: Response, access: string, refresh: string): void {
  const base = {
    httpOnly: true,
    secure:   IS_PROD,
    sameSite: IS_PROD ? ('none' as const) : ('lax' as const),
  };
  res.cookie('access_token',  access,  { ...base, path: '/',                        maxAge: 15 * 60 * 1000 });
  res.cookie('refresh_token', refresh, { ...base, path: '/api/v1/auth/refresh',     maxAge: 7 * 24 * 60 * 60 * 1000 });
}

function clearAuthCookies(res: Response): void {
  const base = { httpOnly: true, secure: IS_PROD, sameSite: IS_PROD ? ('none' as const) : ('lax' as const) };
  res.clearCookie('access_token',  { ...base, path: '/' });
  res.clearCookie('refresh_token', { ...base, path: '/api/v1/auth/refresh' });
}

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Firebase ID Token → JWT propio + cookies HttpOnly' })
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
  @ApiOperation({ summary: 'Sync usuario con Firebase' })
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

    if (!refreshToken) {
      return res.status(HttpStatus.BAD_REQUEST).json({
        success: false, message: 'Refresh token requerido',
      });
    }

    const result = await this.authService.refresh({ refreshToken });
    setAuthCookies(res, result.accessToken, result.refreshToken);
    return result;
  }

  @Public()
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  logout(@Res({ passthrough: true }) res: Response) {
    clearAuthCookies(res);
    return { success: true, message: 'Sesión cerrada' };
  }
}
EOF
ok "src/auth/auth.controller.ts"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Completado${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Archivos modificados:"
echo "    src/auth/guards/firebase-auth.guard.ts"
echo "    src/auth/auth.module.ts"
echo "    src/auth/auth.service.ts"
echo "    src/auth/dto/refresh-token.dto.ts"
echo "    src/auth/auth.controller.ts"
echo ""