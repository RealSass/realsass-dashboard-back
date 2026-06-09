#!/usr/bin/env bash
# =============================================================================
# 1-dashboard-back.sh  —  reescribe archivos completos, sin sed ni awk
# USO: cd <raiz-de-dashboard-back> && bash 1-dashboard-back.sh
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓  $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${NC}"; }
fail() { echo -e "${RED}  ✗  $*${NC}"; exit 1; }
step() { echo -e "\n${BLUE}── $* ──────────────────────────────${NC}"; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════╗"
echo "║  dashboard-back — Firebase SSO endpoint  ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

[[ -f "package.json" ]]                || fail "Corré desde la raíz de dashboard-back"
[[ -f "src/auth/auth.service.ts" ]]    || fail "No encontré src/auth/auth.service.ts"
[[ -f "src/auth/auth.controller.ts" ]] || fail "No encontré src/auth/auth.controller.ts"
[[ -f "src/auth/auth.module.ts" ]]     || fail "No encontré src/auth/auth.module.ts"

# ─── 1. Instalar @nestjs/jwt si no está ──────────────────────────────────────
step "1/5  Dependencias"
if grep -q '"@nestjs/jwt"' package.json; then
  ok "@nestjs/jwt ya está en package.json"
else
  pnpm add @nestjs/jwt
  ok "@nestjs/jwt instalado"
fi

# ─── 2. DTO ──────────────────────────────────────────────────────────────────
step "2/5  src/auth/dto/firebase-sso.dto.ts"
cat > src/auth/dto/firebase-sso.dto.ts << 'EOF'
// src/auth/dto/firebase-sso.dto.ts
import { IsString, IsNotEmpty } from 'class-validator';

export class FirebaseSsoDto {
  @IsString()
  @IsNotEmpty()
  firebaseIdToken: string;
}
EOF
ok "firebase-sso.dto.ts"

# ─── 3. auth.service.ts  (reescritura completa) ───────────────────────────────
step "3/5  src/auth/auth.service.ts"
cat > src/auth/auth.service.ts << 'EOF'
// src/auth/auth.service.ts
import {
  Injectable,
  NotFoundException,
  UnauthorizedException,
  ForbiddenException,
  Inject,
  Logger,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { FIREBASE_ADMIN } from '../firebase/firebase.module';
import type * as admin from 'firebase-admin';
import { SyncAuthDto } from './dto/sync-auth.dto';
import { FirebaseSsoDto } from './dto/firebase-sso.dto';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly jwtService: JwtService,
    @Inject(FIREBASE_ADMIN) private readonly firebase: admin.app.App | null,
  ) {}

  /**
   * POST /api/v1/auth/sync
   * Upsert del usuario en base al firebaseUid.
   */
  async sync(dto: SyncAuthDto) {
    const user = await this.prisma.user.upsert({
      where: { firebaseUid: dto.firebaseUid },
      create: {
        firebaseUid:   dto.firebaseUid,
        firebaseEmail: dto.email,
        email:         dto.email,
        nombre:        dto.nombre ?? dto.email.split('@')[0],
        role:          'AGENTE',
      },
      update: {
        firebaseEmail: dto.email,
        email:         dto.email,
        ...(dto.nombre && { nombre: dto.nombre }),
      },
      select: {
        id:          true,
        email:       true,
        nombre:      true,
        role:        true,
        firebaseUid: true,
        isActive:    true,
        createdAt:   true,
      },
    });

    await this.audit.log({
      action:     'auth.sync',
      entityType: 'User',
      entityId:   user.id,
      userId:     user.id,
      payload:    { email: dto.email },
    });

    return user;
  }

  /**
   * GET /api/v1/auth/me
   */
  async me(firebaseUid: string) {
    const user = await this.prisma.user.findUnique({
      where: { firebaseUid },
      select: {
        id:          true,
        email:       true,
        nombre:      true,
        role:        true,
        firebaseUid: true,
        isActive:    true,
        createdAt:   true,
      },
    });

    if (!user) {
      throw new NotFoundException('Usuario no encontrado. Llamar a /auth/sync primero.');
    }

    return user;
  }

  /**
   * POST /api/v1/auth/firebase-sso
   * Recibe Firebase ID token desde real-front, valida identidad,
   * busca/crea usuario en la DB del dashboard y emite JWT del sistema.
   */
  async firebaseSso(dto: FirebaseSsoDto): Promise<{
    accessToken:  string;
    refreshToken: string;
    user: { id: string; email: string; nombre: string; role: string };
  }> {
    if (!this.firebase) {
      throw new UnauthorizedException('Firebase no configurado en este entorno');
    }

    // 1. Verificar token Firebase
    let decoded: admin.auth.DecodedIdToken;
    try {
      decoded = await this.firebase.auth().verifyIdToken(dto.firebaseIdToken, true);
    } catch (err) {
      this.logger.warn(`SSO token inválido: ${(err as Error).message}`);
      throw new UnauthorizedException('Token de Firebase inválido o expirado');
    }

    const uid   = decoded.uid;
    const email = decoded.email ?? '';

    // 2. Buscar o crear usuario
    let user = await this.prisma.user.findFirst({
      where: { OR: [{ firebaseUid: uid }, { email }] },
      select: { id: true, email: true, nombre: true, role: true, isActive: true, firebaseUid: true },
    });

    if (!user) {
      user = await this.prisma.user.create({
        data: {
          firebaseUid:   uid,
          firebaseEmail: email,
          email,
          nombre: decoded.name ?? email.split('@')[0] ?? 'Usuario',
          role:   'AGENTE',
        },
        select: { id: true, email: true, nombre: true, role: true, isActive: true, firebaseUid: true },
      });
      this.logger.log(`SSO: nuevo usuario creado — ${email}`);
    } else if (!user.firebaseUid) {
      await this.prisma.user.update({
        where: { id: user.id },
        data:  { firebaseUid: uid, firebaseEmail: email },
      });
    }

    // 3. Verificar cuenta activa
    if (!user.isActive) {
      throw new ForbiddenException('Cuenta desactivada. Contactá al administrador.');
    }

    // 4. Emitir JWT
    const payload = { sub: user.id, email: user.email, role: user.role };

    const accessToken = this.jwtService.sign(payload, {
      secret:    process.env['JWT_ACCESS_SECRET']     ?? 'change_me_access',
      expiresIn: process.env['JWT_ACCESS_EXPIRES_IN'] ?? '15m',
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret:    process.env['JWT_REFRESH_SECRET']     ?? 'change_me_refresh',
      expiresIn: process.env['JWT_REFRESH_EXPIRES_IN'] ?? '7d',
    });

    // 5. Persistir refresh token
    await this.prisma.user.update({
      where: { id: user.id },
      data:  { refreshToken },
    });

    await this.audit.log({
      action:     'auth.firebase_sso',
      entityType: 'User',
      entityId:   user.id,
      userId:     user.id,
      payload:    { email: user.email, role: user.role },
    });

    this.logger.log(`SSO exitoso — ${user.email} (${user.role})`);

    return {
      accessToken,
      refreshToken,
      user: { id: user.id, email: user.email, nombre: user.nombre, role: user.role },
    };
  }
}
EOF
ok "auth.service.ts"

# ─── 4. auth.controller.ts  (reescritura completa) ───────────────────────────
step "4/5  src/auth/auth.controller.ts"
cat > src/auth/auth.controller.ts << 'EOF'
// src/auth/auth.controller.ts
import {
  Controller,
  Post,
  Get,
  Body,
  HttpCode,
  HttpStatus,
  Request,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { SyncAuthDto } from './dto/sync-auth.dto';
import { FirebaseSsoDto } from './dto/firebase-sso.dto';
import { Public } from '../common/decorators/public.decorator';
import type { Request as ExpressRequest } from 'express';

@Controller('api/v1/auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /** POST /api/v1/auth/sync */
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  sync(@Body() dto: SyncAuthDto) {
    return this.authService.sync(dto);
  }

  /** GET /api/v1/auth/me */
  @Get('me')
  me(@Request() req: ExpressRequest) {
    const firebaseUid = (req as any).user?.firebaseUid as string;
    return this.authService.me(firebaseUid);
  }

  /**
   * POST /api/v1/auth/firebase-sso
   * Ruta pública. Recibe Firebase ID token de real-front
   * y devuelve accessToken + refreshToken del dashboard.
   */
  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  firebaseSso(@Body() dto: FirebaseSsoDto) {
    return this.authService.firebaseSso(dto);
  }
}
EOF
ok "auth.controller.ts"

# ─── 5. auth.module.ts  (reescritura completa) ───────────────────────────────
step "5/5  src/auth/auth.module.ts"
cat > src/auth/auth.module.ts << 'EOF'
// src/auth/auth.module.ts
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { AuditModule } from '../audit/audit.module';

@Module({
  imports: [
    AuditModule,
    ConfigModule,
    JwtModule.registerAsync({
      imports:    [ConfigModule],
      inject:     [ConfigService],
      useFactory: (cs: ConfigService) => ({
        secret:      cs.get<string>('JWT_ACCESS_SECRET', 'change_me_access'),
        signOptions: { expiresIn: cs.get<string>('JWT_ACCESS_EXPIRES_IN', '15m') },
      }),
    }),
  ],
  controllers: [AuthController],
  providers:   [AuthService],
  exports:     [AuthService],
})
export class AuthModule {}
EOF
ok "auth.module.ts"

echo ""
echo -e "${GREEN}══ dashboard-back listo ══════════════════════════════════════${NC}"
echo "  Archivos reescritos:"
echo "    src/auth/dto/firebase-sso.dto.ts"
echo "    src/auth/auth.service.ts"
echo "    src/auth/auth.controller.ts"
echo "    src/auth/auth.module.ts"
echo ""
echo "  → pnpm start:dev"
echo "  → POST /api/v1/auth/firebase-sso  { firebaseIdToken: string }"
echo ""