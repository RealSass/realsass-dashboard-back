#!/usr/bin/env bash
# =============================================================================
# 1-dashboard-back.sh
# Agrega POST /api/v1/auth/firebase-sso al dashboard-back.
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

# ─── 1. DTO ──────────────────────────────────────────────────────────────────
step "1/4  src/auth/dto/firebase-sso.dto.ts"

cat > src/auth/dto/firebase-sso.dto.ts << 'EOF'
// src/auth/dto/firebase-sso.dto.ts
import { IsString, IsNotEmpty } from 'class-validator';

export class FirebaseSsoDto {
  /** Firebase ID token obtenido con firebaseUser.getIdToken() */
  @IsString()
  @IsNotEmpty()
  firebaseIdToken: string;
}
EOF
ok "src/auth/dto/firebase-sso.dto.ts"

# ─── 2. auth.service.ts ──────────────────────────────────────────────────────
step "2/4  src/auth/auth.service.ts"

if grep -q "firebaseSso" src/auth/auth.service.ts; then
  warn "firebaseSso ya existe — saltando"
else
  # 2a. Reemplazar imports de @nestjs/common (sin | en el contenido — sed funciona)
  sed -i "s|import { Injectable, NotFoundException, Logger } from '@nestjs/common';|import { Injectable, NotFoundException, UnauthorizedException, ForbiddenException, Inject, Logger } from '@nestjs/common';|" \
    src/auth/auth.service.ts

  # 2b. Agregar imports de Jwt + Firebase + DTO después de AuditService (sin | — sed funciona)
  sed -i "s|import { AuditService } from '../audit/audit.service';|import { AuditService } from '../audit/audit.service';\nimport { JwtService } from '@nestjs/jwt';\nimport { FIREBASE_ADMIN } from '../firebase/firebase.module';\nimport type * as admin from 'firebase-admin';\nimport { FirebaseSsoDto } from './dto/firebase-sso.dto';|" \
    src/auth/auth.service.ts

  # 2c. Extender constructor — usa awk porque "App | null" contiene |
  awk '
  /private readonly audit: AuditService,$/ {
    print
    print "    private readonly jwtService: JwtService,"
    print "    @Inject(FIREBASE_ADMIN) private readonly firebase: admin.app.App | null,"
    next
  }
  { print }
  ' src/auth/auth.service.ts > /tmp/auth_service_tmp.ts
  mv /tmp/auth_service_tmp.ts src/auth/auth.service.ts

  # 2d. Agregar método firebaseSso antes del último "}"
  TMPFILE=$(mktemp)
  head -n -1 src/auth/auth.service.ts > "$TMPFILE"

  cat >> "$TMPFILE" << 'ENDMETHOD'

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
      this.logger.warn(`SSO: token inválido — ${(err as Error).message}`);
      throw new UnauthorizedException('Token de Firebase inválido o expirado');
    }

    const uid   = decoded.uid;
    const email = decoded.email ?? '';

    // 2. Buscar o crear usuario en la DB del dashboard
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

    // 4. Emitir JWT del sistema dashboard
    const payload = { sub: user.id, email: user.email, role: user.role };

    const accessToken = this.jwtService.sign(payload, {
      secret:    process.env['JWT_ACCESS_SECRET']      ?? 'change_me_access',
      expiresIn: process.env['JWT_ACCESS_EXPIRES_IN']  ?? '15m',
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
ENDMETHOD

  mv "$TMPFILE" src/auth/auth.service.ts
  ok "src/auth/auth.service.ts — firebaseSso() agregado"
fi

# ─── 3. auth.controller.ts ───────────────────────────────────────────────────
step "3/4  src/auth/auth.controller.ts"

if grep -q "firebase-sso" src/auth/auth.controller.ts; then
  warn "Endpoint ya existe — saltando"
else
  # Agregar import del DTO (sin | — sed funciona)
  sed -i "s|import { SyncAuthDto } from './dto/sync-auth.dto';|import { SyncAuthDto } from './dto/sync-auth.dto';\nimport { FirebaseSsoDto } from './dto/firebase-sso.dto';|" \
    src/auth/auth.controller.ts

  # Agregar endpoint antes del último "}"
  TMPFILE=$(mktemp)
  head -n -1 src/auth/auth.controller.ts > "$TMPFILE"

  cat >> "$TMPFILE" << 'ENDMETHOD'

  /**
   * POST /api/v1/auth/firebase-sso
   * Ruta pública. Recibe Firebase ID token de real-front y devuelve
   * accessToken + refreshToken del sistema dashboard.
   */
  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  firebaseSso(@Body() dto: FirebaseSsoDto) {
    return this.authService.firebaseSso(dto);
  }
}
ENDMETHOD

  mv "$TMPFILE" src/auth/auth.controller.ts
  ok "src/auth/auth.controller.ts — POST firebase-sso agregado"
fi

# ─── 4. auth.module.ts ───────────────────────────────────────────────────────
step "4/4  src/auth/auth.module.ts"

if grep -q "JwtModule" src/auth/auth.module.ts; then
  warn "JwtModule ya registrado — saltando"
else
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
  ok "src/auth/auth.module.ts — JwtModule registrado"
fi

# ─── Verificar .env ───────────────────────────────────────────────────────────
echo ""
if [[ -f ".env" ]]; then
  grep -q "JWT_ACCESS_SECRET"   .env && ok  ".env JWT_ACCESS_SECRET ✓"   || warn ".env — falta JWT_ACCESS_SECRET"
  grep -q "JWT_REFRESH_SECRET"  .env && ok  ".env JWT_REFRESH_SECRET ✓"  || warn ".env — falta JWT_REFRESH_SECRET"
  grep -q "FIREBASE_PROJECT_ID" .env && ok  ".env FIREBASE_PROJECT_ID ✓" || warn ".env — falta FIREBASE_PROJECT_ID"
fi

echo ""
echo -e "${GREEN}══ dashboard-back listo ══════════════════════════════════════${NC}"
echo "  Endpoint: POST /api/v1/auth/firebase-sso"
echo "  Body:     { \"firebaseIdToken\": \"<token>\" }"
echo "  Response: { \"data\": { accessToken, refreshToken, user } }"
echo "  → pnpm start:dev"
echo ""