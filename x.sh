#!/usr/bin/env bash
# =============================================================================
# fix-controllers-prefix.sh
# Quita el prefijo api/v1 de los @Controller porque ya está en setGlobalPrefix
# USO: cd <raiz-de-dashboard-back> && bash fix-controllers-prefix.sh
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓  $*${NC}"; }
step() { echo -e "\n${BLUE}── $* ──────────────────────────────${NC}"; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════╗"
echo "║  dashboard-back — fix @Controller prefix ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ─── auth.controller.ts ──────────────────────────────────────────────────────
step "src/auth/auth.controller.ts"
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

@Controller('auth')
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
ok "auth.controller.ts — @Controller('auth')"

# ─── zonas.controller.ts ─────────────────────────────────────────────────────
step "src/zonas/zonas.controller.ts"
if [[ -f "src/zonas/zonas.controller.ts" ]]; then
  # Reemplazar @Controller('api/v1/zonas') por @Controller('zonas')
  LC_ALL=C sed -i "s|@Controller('api/v1/zonas')|@Controller('zonas')|g" src/zonas/zonas.controller.ts
  ok "zonas.controller.ts — @Controller('zonas')"
else
  ok "zonas.controller.ts — no existe, saltando"
fi

# ─── propiedades.controller.ts ───────────────────────────────────────────────
step "src/propiedades/propiedades.controller.ts"
if [[ -f "src/propiedades/propiedades.controller.ts" ]]; then
  LC_ALL=C sed -i "s|@Controller('api/v1/propiedades')|@Controller('propiedades')|g" src/propiedades/propiedades.controller.ts
  ok "propiedades.controller.ts — @Controller('propiedades')"
else
  ok "propiedades.controller.ts — no existe, saltando"
fi

# ─── Buscar cualquier otro controller con api/v1 hardcodeado ─────────────────
step "Verificando controllers restantes"
REMAINING=$(grep -r "@Controller('api/v1" src/ --include="*.ts" -l 2>/dev/null || true)
if [[ -n "$REMAINING" ]]; then
  echo "$REMAINING" | while read -r file; do
    LC_ALL=C sed -i "s|@Controller('api/v1/\([^']*\)')|@Controller('\1')|g" "$file"
    ok "$file — prefijo api/v1 eliminado"
  done
else
  ok "No quedan controllers con api/v1 hardcodeado"
fi

echo ""
echo -e "${GREEN}══ listo ═════════════════════════════════════════════════════${NC}"
echo "  Todos los controllers usan rutas relativas."
echo "  El setGlobalPrefix('api/v1') en main.ts las prefija automáticamente."
echo ""
echo "  Rutas resultantes:"
echo "    POST /api/v1/auth/sync"
echo "    GET  /api/v1/auth/me"
echo "    POST /api/v1/auth/firebase-sso"
echo "    GET  /api/v1/zonas"
echo "    GET  /api/v1/propiedades"
echo ""
echo "  → pnpm run build"
echo ""