#!/usr/bin/env bash
# =============================================================================
# fix-dashboard-back.sh
# Corrige el error de tipos de expiresIn en @nestjs/jwt v11
# USO: cd <raiz-de-dashboard-back> && bash fix-dashboard-back.sh
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓  $*${NC}"; }
step() { echo -e "\n${BLUE}── $* ──────────────────────────────${NC}"; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════╗"
echo "║  dashboard-back — fix expiresIn types    ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ─── 1. auth.module.ts ───────────────────────────────────────────────────────
step "1/2  src/auth/auth.module.ts"

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
        signOptions: {
          // cast necesario: @nestjs/jwt v11 exige StringValue, no string genérico
          expiresIn: (cs.get<string>('JWT_ACCESS_EXPIRES_IN', '15m')) as any,
        },
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

# ─── 2. auth.service.ts — solo los dos jwtService.sign ───────────────────────
step "2/2  src/auth/auth.service.ts"

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

  /** POST /api/v1/auth/sync */
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
        id: true, email: true, nombre: true, role: true,
        firebaseUid: true, isActive: true, createdAt: true,
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

  /** GET /api/v1/auth/me */
  async me(firebaseUid: string) {
    const user = await this.prisma.user.findUnique({
      where:  { firebaseUid },
      select: {
        id: true, email: true, nombre: true, role: true,
        firebaseUid: true, isActive: true, createdAt: true,
      },
    });

    if (!user) {
      throw new NotFoundException('Usuario no encontrado. Llamar a /auth/sync primero.');
    }

    return user;
  }

  /** POST /api/v1/auth/firebase-sso */
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
      where:  { OR: [{ firebaseUid: uid }, { email }] },
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
      this.logger.log(`SSO: nuevo usuario — ${email}`);
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
    // "as any" necesario: @nestjs/jwt v11 exige StringValue en expiresIn,
    // pero process.env devuelve string genérico — en runtime el valor es correcto.
    const payload = { sub: user.id, email: user.email, role: user.role };

    const accessToken = this.jwtService.sign(payload, {
      secret:    process.env['JWT_ACCESS_SECRET']     ?? 'change_me_access',
      expiresIn: (process.env['JWT_ACCESS_EXPIRES_IN'] ?? '15m') as any,
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret:    process.env['JWT_REFRESH_SECRET']     ?? 'change_me_refresh',
      expiresIn: (process.env['JWT_REFRESH_EXPIRES_IN'] ?? '7d') as any,
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

echo ""
echo -e "${GREEN}══ listo — volvé a buildear ══════════════════════════════════${NC}"
echo "  → pnpm run build"
echo ""