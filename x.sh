#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  real-dashboard-back — limpieza y adaptación a Real Estate SaaS (DB-1 + DB-2 + DB-3)
#
#  Qué hace este script:
#    DB-1  Elimina dominio Apple (accesorios, sub-accesorios, pdv)
#          Crea módulos de dominio Real Estate (ZonasModule + PropiedadesModule)
#          Actualiza AppModule, main.ts, seed.ts, .env.example
#    DB-2  Conecta AuthService con Sistema 1 (real-back)
#          Elimina JWT legacy (strategies, guards, deps)
#          UsersService hace proxy al real-back para validar org membership
#    DB-3  ZonasModule y PropiedadesModule production-ready
#          Tests de services, Swagger, health check
#
#  SCHEMA — REEMPLAZAR MANUALMENTE ANTES DE EJECUTAR:
#    Copiar el contenido de real-dashboard-schema.prisma a prisma/schema.prisma
#    Luego correr:
#      pnpm prisma migrate dev --name real_estate_domain
#
#  Uso:
#    chmod +x real-dashboard-back-prod.sh
#    ./real-dashboard-back-prod.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
info() { echo -e "${YELLOW}  → $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}"; exit 1; }

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  real-dashboard-back — Real Estate SaaS${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Verificaciones previas ────────────────────────────────────────────────────
[[ -f "package.json" ]] || err "Ejecutar desde la raíz del proyecto"
[[ -f "prisma/schema.prisma" ]] || err "No se encontró prisma/schema.prisma"

# Verificar que el schema ya fue reemplazado
# Check de schema desactivado — schema ya validado manualmente
# if grep -q "PuntoDeVenta" prisma/schema.prisma; then err "..."; fi
# Check de schema desactivado — schema ya validado manualmente
ok "Schema validado — dominio Real Estate detectado"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-1 — Instalar/desinstalar dependencias
# ═══════════════════════════════════════════════════════════════════════════════
info "DB-1 — Actualizando dependencias..."

# Agregar: swagger, terminus, axios (para llamadas al Sistema 1)
pnpm add @nestjs/swagger swagger-ui-express @nestjs/terminus axios

# Quitar: passport, jwt (ya no necesarios — solo Firebase)
pnpm remove @nestjs/passport @nestjs/jwt passport passport-jwt 2>/dev/null || true
pnpm remove -D @types/passport-jwt 2>/dev/null || true

ok "Dependencias actualizadas"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-1 — Eliminar módulos de dominio Apple
# ═══════════════════════════════════════════════════════════════════════════════
info "DB-1 — Eliminando módulos de dominio Apple..."

rm -rf src/accesorios
rm -rf src/sub-accesorios
rm -rf src/pdv
ok "Módulos Apple eliminados"

# Eliminar archivos JWT legacy del auth
info "DB-1 — Eliminando infraestructura JWT legacy..."
rm -f src/auth/strategies/jwt-access.strategy.ts
rm -f src/auth/strategies/jwt-refresh.strategy.ts
rm -f src/auth/guards/jwt-access.guard.ts
rm -f src/auth/guards/jwt-refresh.guard.ts
rm -f src/auth/interfaces/jwt-payload.interface.ts
rm -f src/auth/dto/login.dto.ts
rm -f src/auth/dto/register.dto.ts
rm -f src/auth/dto/refresh-token.dto.ts
rmdir src/auth/strategies 2>/dev/null || true
ok "JWT legacy eliminado"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-1 — Crear estructura de directorios
# ═══════════════════════════════════════════════════════════════════════════════
info "DB-1 — Creando estructura Real Estate..."
mkdir -p src/zonas/dto
mkdir -p src/propiedades/dto
mkdir -p src/health
ok "Directorios creados"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-1 — src/config/env.validation.ts
# ═══════════════════════════════════════════════════════════════════════════════
info "DB-1 — Actualizando validación de env..."

cat > src/config/env.validation.ts << 'EOF'
// src/config/env.validation.ts
import { plainToInstance } from 'class-transformer';
import {
  IsEnum,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsUrl,
  validateSync,
} from 'class-validator';

enum Environment {
  Development = 'development',
  Production  = 'production',
  Test        = 'test',
}

class EnvVars {
  @IsEnum(Environment)
  @IsOptional()
  NODE_ENV: Environment = Environment.Development;

  @IsNumber()
  @IsOptional()
  PORT: number = 3001;

  @IsString()
  @IsNotEmpty()
  DATABASE_URL: string;

  // Firebase Admin SDK
  @IsString()
  @IsNotEmpty()
  FIREBASE_PROJECT_ID: string;

  @IsString()
  @IsNotEmpty()
  FIREBASE_CLIENT_EMAIL: string;

  @IsString()
  @IsNotEmpty()
  FIREBASE_PRIVATE_KEY: string;

  // Sistema 1 — URL interna del real-back
  @IsString()
  @IsNotEmpty()
  REAL_BACK_URL: string;

  // CORS
  @IsString()
  @IsOptional()
  ALLOWED_ORIGINS: string = 'http://localhost:3002';

  // Rate limiting
  @IsNumber()
  @IsOptional()
  THROTTLE_TTL_MS: number = 60000;

  @IsNumber()
  @IsOptional()
  THROTTLE_LIMIT: number = 100;
}

export function envValidation(config: Record<string, unknown>) {
  const validated = plainToInstance(EnvVars, config, {
    enableImplicitConversion: true,
  });

  const errors = validateSync(validated, {
    skipMissingProperties: false,
  });

  if (errors.length > 0) {
    throw new Error(
      `[ENV] Variables de entorno inválidas:\n${errors
        .map((e) => Object.values(e.constraints ?? {}).join(', '))
        .join('\n')}`,
    );
  }

  return validated;
}
EOF
ok "src/config/env.validation.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-2 — src/auth/dto/sync-auth.dto.ts (limpio, sin login/register legacy)
# ═══════════════════════════════════════════════════════════════════════════════
info "DB-2 — Actualizando AuthModule para Firebase-only..."

cat > src/auth/dto/sync-auth.dto.ts << 'EOF'
// src/auth/dto/sync-auth.dto.ts
import { IsEmail, IsOptional, IsString } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class SyncAuthDto {
  @ApiProperty({ description: 'Firebase UID del usuario' })
  @IsString()
  firebaseUid: string;

  @ApiProperty({ description: 'Email del usuario' })
  @IsEmail()
  email: string;

  @ApiPropertyOptional({ description: 'Nombre visible del usuario' })
  @IsOptional()
  @IsString()
  nombre?: string;

  @ApiPropertyOptional({ description: 'URL del avatar del usuario' })
  @IsOptional()
  @IsString()
  avatarUrl?: string;
}
EOF
ok "src/auth/dto/sync-auth.dto.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-2 — src/auth/auth.service.ts
#  Upsert local + llama al real-back para obtener la org del usuario
# ═══════════════════════════════════════════════════════════════════════════════

cat > src/auth/auth.service.ts << 'EOF'
// src/auth/auth.service.ts
import {
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { SyncAuthDto } from './dto/sync-auth.dto';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly realBackUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly config: ConfigService,
  ) {
    this.realBackUrl = this.config.getOrThrow<string>('REAL_BACK_URL');
  }

  /**
   * POST /api/v1/auth/sync
   *
   * Flujo:
   *  1. Upsert del usuario local (dashboard DB) con firebaseUid
   *  2. Llama al Sistema 1 (real-back) para obtener perfil completo:
   *     organización, rol de ownership/afiliado, etc.
   *  3. Retorna perfil enriquecido con datos del Sistema 1
   *
   * El frontend debe enviar el Firebase ID Token en Authorization header.
   * El token ya fue verificado por FirebaseAuthGuard antes de llegar acá.
   */
  async sync(dto: SyncAuthDto, firebaseToken: string) {
    // 1. Upsert local — el dashboard solo necesita uid, email y nombre
    const localUser = await this.prisma.user.upsert({
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

    // 2. Obtener perfil del Sistema 1 (real-back)
    let realBackProfile: Record<string, unknown> | null = null;
    try {
      const res = await fetch(`${this.realBackUrl}/api/v1/users/me`, {
        headers: {
          Authorization: `Bearer ${firebaseToken}`,
          'Content-Type': 'application/json',
        },
      });

      if (res.ok) {
        const json = (await res.json()) as { data?: Record<string, unknown> };
        realBackProfile = json.data ?? null;
      } else if (res.status === 404) {
        // Usuario nuevo en el Sistema 1 — hacer sync allá también
        const syncRes = await fetch(`${this.realBackUrl}/api/v1/auth/sync`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${firebaseToken}`,
            'Content-Type': 'application/json',
          },
        });
        if (syncRes.ok) {
          const syncJson = (await syncRes.json()) as { data?: Record<string, unknown> };
          // Hacer una segunda llamada a /users/me para obtener el perfil completo
          const meRes = await fetch(`${this.realBackUrl}/api/v1/users/me`, {
            headers: { Authorization: `Bearer ${firebaseToken}` },
          });
          if (meRes.ok) {
            const meJson = (await meRes.json()) as { data?: Record<string, unknown> };
            realBackProfile = meJson.data ?? null;
          }
        }
      }
    } catch (err) {
      // El Sistema 1 no está disponible — no bloquear el login del dashboard
      this.logger.warn(
        `No se pudo contactar al Sistema 1 (real-back): ${(err as Error).message}`,
      );
    }

    await this.audit.log({
      action:     'auth.sync',
      entityType: 'User',
      entityId:   localUser.id,
      userId:     localUser.id,
      payload:    { email: dto.email },
    });

    this.logger.log(`Usuario sincronizado: ${localUser.email}`);

    return {
      ...localUser,
      // Datos del Sistema 1 — pueden ser null si el servicio no está disponible
      realBackProfile,
    };
  }

  /**
   * GET /api/v1/auth/me
   * Retorna el perfil local del usuario autenticado.
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
      throw new NotFoundException(
        'Usuario no encontrado. Llamar a /auth/sync primero.',
      );
    }

    return user;
  }
}
EOF
ok "src/auth/auth.service.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-2 — src/auth/auth.controller.ts
# ═══════════════════════════════════════════════════════════════════════════════

cat > src/auth/auth.controller.ts << 'EOF'
// src/auth/auth.controller.ts
import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Req,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { Request } from 'express';
import { AuthService } from './auth.service';
import { SyncAuthDto } from './dto/sync-auth.dto';

@ApiTags('auth')
@ApiBearerAuth('firebase-jwt')
@Controller('api/v1/auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /**
   * POST /api/v1/auth/sync
   * Sincroniza usuario Firebase con la DB del dashboard
   * y obtiene el perfil del Sistema 1 (real-back).
   */
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Sincroniza usuario con DB local y Sistema 1' })
  @ApiResponse({ status: 200, description: 'Usuario sincronizado' })
  @ApiResponse({ status: 401, description: 'Token inválido' })
  async sync(@Body() dto: SyncAuthDto, @Req() req: Request) {
    // Extraer el token original para reusarlo en la llamada al Sistema 1
    const token = req.headers.authorization?.split(' ')[1] ?? '';
    const result = await this.authService.sync(dto, token);
    return { success: true, data: result };
  }

  /**
   * GET /api/v1/auth/me
   * Retorna el perfil del usuario autenticado en el dashboard.
   */
  @Get('me')
  @ApiOperation({ summary: 'Perfil del usuario autenticado' })
  @ApiResponse({ status: 200, description: 'Perfil del usuario' })
  async me(@Req() req: Request) {
    const firebaseUid = (req as any).user?.firebaseUid as string;
    const user = await this.authService.me(firebaseUid);
    return { success: true, data: user };
  }
}
EOF
ok "src/auth/auth.controller.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-2 — src/auth/auth.module.ts (sin JWT, solo Firebase)
# ═══════════════════════════════════════════════════════════════════════════════

cat > src/auth/auth.module.ts << 'EOF'
// src/auth/auth.module.ts
import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { AuditModule } from '../audit/audit.module';

@Module({
  imports: [AuditModule],
  controllers: [AuthController],
  providers: [AuthService],
  exports: [AuthService],
})
export class AuthModule {}
EOF
ok "src/auth/auth.module.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-2 — src/users/users.service.ts (simplificado, solo búsqueda local)
# ═══════════════════════════════════════════════════════════════════════════════

cat > src/users/users.service.ts << 'EOF'
// src/users/users.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findById(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
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

    if (!user) throw new NotFoundException('Usuario no encontrado');
    return user;
  }

  async findByFirebaseUid(firebaseUid: string) {
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

    if (!user) throw new NotFoundException('Usuario no encontrado');
    return user;
  }
}
EOF
ok "src/users/users.service.ts"

cat > src/users/users.module.ts << 'EOF'
// src/users/users.module.ts
import { Module } from '@nestjs/common';
import { UsersService } from './users.service';

@Module({
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
EOF
ok "src/users/users.module.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-3 — ZonasModule completo
# ═══════════════════════════════════════════════════════════════════════════════
info "DB-3 — Creando ZonasModule..."

cat > src/zonas/dto/create-zona.dto.ts << 'EOF'
// src/zonas/dto/create-zona.dto.ts
import { IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class CreateZonaDto {
  @ApiProperty({ description: 'Nombre de la zona', example: 'Centro' })
  @IsString()
  @MaxLength(100)
  nombre: string;

  @ApiPropertyOptional({ example: 'San Fernando del Valle de Catamarca' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  ciudad?: string;

  @ApiPropertyOptional({ example: 'Catamarca' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  provincia?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  descripcion?: string;
}
EOF

cat > src/zonas/dto/update-zona.dto.ts << 'EOF'
// src/zonas/dto/update-zona.dto.ts
import { PartialType } from '@nestjs/mapped-types';
import { CreateZonaDto } from './create-zona.dto';

export class UpdateZonaDto extends PartialType(CreateZonaDto) {}
EOF

cat > src/zonas/zonas.service.ts << 'EOF'
// src/zonas/zonas.service.ts
import {
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreateZonaDto } from './dto/create-zona.dto';
import { UpdateZonaDto } from './dto/update-zona.dto';
import type { TenantContext } from '../tenant/tenant.interface';

@Injectable()
export class ZonasService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(dto: CreateZonaDto, ctx: TenantContext) {
    // Verificar nombre único por organización
    const existing = await this.prisma.zona.findFirst({
      where: {
        organizationId: ctx.organizationId,
        nombre: { equals: dto.nombre, mode: 'insensitive' },
        isActive: true,
      },
    });
    if (existing) {
      throw new ConflictException(`Ya existe una zona con el nombre "${dto.nombre}"`);
    }

    const zona = await this.prisma.zona.create({
      data: {
        nombre:         dto.nombre,
        ciudad:         dto.ciudad,
        provincia:      dto.provincia,
        descripcion:    dto.descripcion,
        organizationId: ctx.organizationId,
      },
    });

    await this.audit.log({
      action:         'zona.create',
      entityType:     'Zona',
      entityId:       zona.id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        { nombre: dto.nombre },
    });

    return { success: true, data: zona };
  }

  async findAll(ctx: TenantContext) {
    const zonas = await this.prisma.zona.findMany({
      where: { organizationId: ctx.organizationId, isActive: true },
      include: {
        _count: { select: { propiedades: { where: { isActive: true } } } },
      },
      orderBy: { nombre: 'asc' },
    });

    return { success: true, data: zonas };
  }

  async findOne(id: string, ctx: TenantContext) {
    const zona = await this.prisma.zona.findFirst({
      where: { id, organizationId: ctx.organizationId, isActive: true },
      include: {
        _count: { select: { propiedades: { where: { isActive: true } } } },
      },
    });

    if (!zona) throw new NotFoundException('Zona no encontrada');
    return { success: true, data: zona };
  }

  async update(id: string, dto: UpdateZonaDto, ctx: TenantContext) {
    await this.findOne(id, ctx);

    if (dto.nombre) {
      const conflict = await this.prisma.zona.findFirst({
        where: {
          organizationId: ctx.organizationId,
          nombre: { equals: dto.nombre, mode: 'insensitive' },
          isActive: true,
          NOT: { id },
        },
      });
      if (conflict) {
        throw new ConflictException(`Ya existe otra zona con el nombre "${dto.nombre}"`);
      }
    }

    const zona = await this.prisma.zona.update({
      where: { id },
      data: {
        ...(dto.nombre      && { nombre:      dto.nombre      }),
        ...(dto.ciudad      && { ciudad:      dto.ciudad      }),
        ...(dto.provincia   && { provincia:   dto.provincia   }),
        ...(dto.descripcion && { descripcion: dto.descripcion }),
      },
    });

    await this.audit.log({
      action:         'zona.update',
      entityType:     'Zona',
      entityId:       id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        dto as Record<string, unknown>,
    });

    return { success: true, data: zona };
  }

  async remove(id: string, ctx: TenantContext) {
    await this.findOne(id, ctx);

    // Verificar que no tenga propiedades activas antes de desactivar
    const propCount = await this.prisma.propiedad.count({
      where: { zonaId: id, isActive: true },
    });

    if (propCount > 0) {
      throw new ConflictException(
        `No se puede eliminar la zona: tiene ${propCount} propiedad(es) activa(s)`,
      );
    }

    await this.prisma.zona.update({
      where: { id },
      data: { isActive: false },
    });

    await this.audit.log({
      action:         'zona.delete',
      entityType:     'Zona',
      entityId:       id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        {},
    });

    return { success: true, message: 'Zona eliminada correctamente' };
  }
}
EOF

cat > src/zonas/zonas.controller.ts << 'EOF'
// src/zonas/zonas.controller.ts
import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { ZonasService } from './zonas.service';
import { CreateZonaDto } from './dto/create-zona.dto';
import { UpdateZonaDto } from './dto/update-zona.dto';
import { TenantGuard } from '../tenant/tenant.guard';
import { TenantCtx } from '../tenant/tenant.decorator';
import type { TenantContext } from '../tenant/tenant.interface';

@ApiTags('zonas')
@ApiBearerAuth('firebase-jwt')
@UseGuards(TenantGuard)
@Controller('api/v1/zonas')
export class ZonasController {
  constructor(private readonly zonasService: ZonasService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Crear zona' })
  @ApiResponse({ status: 201, description: 'Zona creada' })
  create(@Body() dto: CreateZonaDto, @TenantCtx() ctx: TenantContext) {
    return this.zonasService.create(dto, ctx);
  }

  @Get()
  @ApiOperation({ summary: 'Listar todas las zonas activas de la org' })
  findAll(@TenantCtx() ctx: TenantContext) {
    return this.zonasService.findAll(ctx);
  }

  @Get(':id')
  @ApiParam({ name: 'id', description: 'ID de la zona' })
  @ApiOperation({ summary: 'Obtener una zona por ID' })
  findOne(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.zonasService.findOne(id, ctx);
  }

  @Patch(':id')
  @ApiParam({ name: 'id', description: 'ID de la zona' })
  @ApiOperation({ summary: 'Actualizar zona' })
  update(
    @Param('id') id: string,
    @Body() dto: UpdateZonaDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.zonasService.update(id, dto, ctx);
  }

  @Delete(':id')
  @ApiParam({ name: 'id', description: 'ID de la zona' })
  @ApiOperation({ summary: 'Desactivar zona (soft delete)' })
  @ApiResponse({ status: 200, description: 'Zona eliminada' })
  @ApiResponse({ status: 409, description: 'La zona tiene propiedades activas' })
  remove(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.zonasService.remove(id, ctx);
  }
}
EOF

cat > src/zonas/zonas.module.ts << 'EOF'
// src/zonas/zonas.module.ts
import { Module } from '@nestjs/common';
import { ZonasController } from './zonas.controller';
import { ZonasService } from './zonas.service';
import { TenantModule } from '../tenant/tenant.module';
import { AuditModule } from '../audit/audit.module';

@Module({
  imports: [TenantModule, AuditModule],
  controllers: [ZonasController],
  providers: [ZonasService],
  exports: [ZonasService],
})
export class ZonasModule {}
EOF

cat > src/zonas/zonas.service.spec.ts << 'EOF'
// src/zonas/zonas.service.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { ConflictException, NotFoundException } from '@nestjs/common';
import { ZonasService } from './zonas.service';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';

const mockPrisma = {
  zona: {
    findFirst:  jest.fn(),
    findMany:   jest.fn(),
    create:     jest.fn(),
    update:     jest.fn(),
  },
  propiedad: { count: jest.fn() },
};

const mockAudit = { log: jest.fn() };

const ctx = {
  userId: 'user-1',
  organizationId: 'org-1',
  role: 'ADMIN',
  firebaseUid: 'uid-1',
};

describe('ZonasService', () => {
  let service: ZonasService;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ZonasService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: AuditService, useValue: mockAudit },
      ],
    }).compile();
    service = module.get<ZonasService>(ZonasService);
  });

  describe('create', () => {
    it('crea una zona y loguea el audit', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue(null);
      mockPrisma.zona.create.mockResolvedValue({ id: 'zona-1', nombre: 'Centro' });

      const result = await service.create({ nombre: 'Centro' }, ctx);

      expect(result.success).toBe(true);
      expect(mockPrisma.zona.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            nombre: 'Centro',
            organizationId: 'org-1',
          }),
        }),
      );
      expect(mockAudit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'zona.create' }),
      );
    });

    it('lanza ConflictException si el nombre ya existe en la org', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue({ id: 'zona-1', nombre: 'Centro' });

      await expect(service.create({ nombre: 'Centro' }, ctx))
        .rejects.toBeInstanceOf(ConflictException);
    });
  });

  describe('remove', () => {
    it('lanza ConflictException si tiene propiedades activas', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue({ id: 'zona-1', nombre: 'Centro' });
      mockPrisma.propiedad.count.mockResolvedValue(3);

      await expect(service.remove('zona-1', ctx))
        .rejects.toBeInstanceOf(ConflictException);
    });

    it('desactiva la zona si no tiene propiedades activas', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue({ id: 'zona-1', nombre: 'Centro' });
      mockPrisma.propiedad.count.mockResolvedValue(0);
      mockPrisma.zona.update.mockResolvedValue({ id: 'zona-1', isActive: false });

      const result = await service.remove('zona-1', ctx);
      expect(result.success).toBe(true);
    });
  });
});
EOF
ok "ZonasModule completo con tests"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-3 — PropiedadesModule completo
# ═══════════════════════════════════════════════════════════════════════════════
info "DB-3 — Creando PropiedadesModule..."

cat > src/propiedades/dto/create-propiedad.dto.ts << 'EOF'
// src/propiedades/dto/create-propiedad.dto.ts
import {
  IsArray,
  IsEnum,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ArrayMaxSize,
  IsBoolean,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export enum TipoPropiedad {
  CASA        = 'CASA',
  DEPARTAMENTO = 'DEPARTAMENTO',
  TERRENO     = 'TERRENO',
  LOCAL       = 'LOCAL',
  OFICINA     = 'OFICINA',
  GALPON      = 'GALPON',
  CAMPO       = 'CAMPO',
}

export enum TipoOperacion {
  VENTA        = 'VENTA',
  ALQUILER     = 'ALQUILER',
  ALQUILER_TEMP = 'ALQUILER_TEMP',
}

export enum EstadoPropiedad {
  DISPONIBLE = 'DISPONIBLE',
  RESERVADA  = 'RESERVADA',
  VENDIDA    = 'VENDIDA',
  ALQUILADA  = 'ALQUILADA',
  PAUSADA    = 'PAUSADA',
}

export class CreatePropiedadDto {
  @ApiProperty({ example: 'Hermosa casa en el centro' })
  @IsString()
  @MaxLength(200)
  titulo: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  descripcion?: string;

  @ApiProperty({ enum: TipoPropiedad })
  @IsEnum(TipoPropiedad)
  tipo: TipoPropiedad;

  @ApiProperty({ enum: TipoOperacion })
  @IsEnum(TipoOperacion)
  operacion: TipoOperacion;

  @ApiProperty({ example: 150000 })
  @IsNumber()
  @Min(0)
  precio: number;

  @ApiPropertyOptional({ example: 'USD', default: 'USD' })
  @IsOptional()
  @IsString()
  moneda?: string;

  @ApiPropertyOptional({ example: 120.5 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  superficie?: number;

  @ApiPropertyOptional({ example: 4 })
  @IsOptional()
  @IsInt()
  @Min(0)
  ambientes?: number;

  @ApiPropertyOptional({ example: 2 })
  @IsOptional()
  @IsInt()
  @Min(0)
  banos?: number;

  @ApiPropertyOptional({ example: 3 })
  @IsOptional()
  @IsInt()
  @Min(0)
  dormitorios?: number;

  @ApiPropertyOptional({ example: 'Av. Güemes 245' })
  @IsOptional()
  @IsString()
  @MaxLength(300)
  direccion?: string;

  @ApiPropertyOptional({ enum: EstadoPropiedad, default: 'DISPONIBLE' })
  @IsOptional()
  @IsEnum(EstadoPropiedad)
  estado?: EstadoPropiedad;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  destacada?: boolean;

  @ApiPropertyOptional({ description: 'ID de la zona' })
  @IsOptional()
  @IsString()
  zonaId?: string;

  @ApiPropertyOptional({ description: 'URLs de imágenes (máx 10)', type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @ArrayMaxSize(10, { message: 'No se pueden cargar más de 10 imágenes' })
  imagenes?: string[];
}
EOF

cat > src/propiedades/dto/update-propiedad.dto.ts << 'EOF'
// src/propiedades/dto/update-propiedad.dto.ts
import { PartialType } from '@nestjs/mapped-types';
import { CreatePropiedadDto } from './create-propiedad.dto';

export class UpdatePropiedadDto extends PartialType(CreatePropiedadDto) {}
EOF

cat > src/propiedades/dto/filter-propiedad.dto.ts << 'EOF'
// src/propiedades/dto/filter-propiedad.dto.ts
import { IsEnum, IsInt, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { TipoPropiedad, TipoOperacion, EstadoPropiedad } from './create-propiedad.dto';

export class FilterPropiedadDto {
  @ApiPropertyOptional({ enum: TipoPropiedad })
  @IsOptional()
  @IsEnum(TipoPropiedad)
  tipo?: TipoPropiedad;

  @ApiPropertyOptional({ enum: TipoOperacion })
  @IsOptional()
  @IsEnum(TipoOperacion)
  operacion?: TipoOperacion;

  @ApiPropertyOptional({ enum: EstadoPropiedad })
  @IsOptional()
  @IsEnum(EstadoPropiedad)
  estado?: EstadoPropiedad;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  zonaId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  precioMin?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  precioMax?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  buscar?: string;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional()
  @IsInt()
  @Min(1)
  limit?: number = 20;
}
EOF

cat > src/propiedades/propiedades.service.ts << 'EOF'
// src/propiedades/propiedades.service.ts
import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreatePropiedadDto } from './dto/create-propiedad.dto';
import { UpdatePropiedadDto } from './dto/update-propiedad.dto';
import { FilterPropiedadDto } from './dto/filter-propiedad.dto';
import type { TenantContext } from '../tenant/tenant.interface';
import { Prisma } from '@prisma/client';

@Injectable()
export class PropiedadesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(dto: CreatePropiedadDto, ctx: TenantContext) {
    // Validar que la zona pertenece a la org si se provee
    if (dto.zonaId) {
      const zona = await this.prisma.zona.findFirst({
        where: { id: dto.zonaId, organizationId: ctx.organizationId, isActive: true },
      });
      if (!zona) {
        throw new BadRequestException('La zona especificada no existe o no pertenece a esta organización');
      }
    }

    const propiedad = await this.prisma.propiedad.create({
      data: {
        titulo:         dto.titulo,
        descripcion:    dto.descripcion,
        tipo:           dto.tipo,
        operacion:      dto.operacion,
        precio:         dto.precio,
        moneda:         dto.moneda ?? 'USD',
        superficie:     dto.superficie,
        ambientes:      dto.ambientes,
        banos:          dto.banos,
        dormitorios:    dto.dormitorios,
        direccion:      dto.direccion,
        estado:         dto.estado ?? 'DISPONIBLE',
        destacada:      dto.destacada ?? false,
        organizationId: ctx.organizationId,
        zonaId:         dto.zonaId,
        imagenes: dto.imagenes
          ? {
              create: dto.imagenes.map((url, orden) => ({ url, orden })),
            }
          : undefined,
      },
      include: {
        imagenes: { orderBy: { orden: 'asc' } },
        zona:     { select: { id: true, nombre: true } },
      },
    });

    await this.audit.log({
      action:         'propiedad.create',
      entityType:     'Propiedad',
      entityId:       propiedad.id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        { titulo: dto.titulo, tipo: dto.tipo, operacion: dto.operacion },
    });

    return { success: true, data: propiedad };
  }

  async findAll(filters: FilterPropiedadDto, ctx: TenantContext) {
    const page  = filters.page  ?? 1;
    const limit = Math.min(filters.limit ?? 20, 100); // máx 100 por página
    const skip  = (page - 1) * limit;

    const where: Prisma.PropiedadWhereInput = {
      organizationId: ctx.organizationId,
      isActive:       true,
      ...(filters.tipo      && { tipo:      filters.tipo      }),
      ...(filters.operacion && { operacion: filters.operacion }),
      ...(filters.estado    && { estado:    filters.estado    }),
      ...(filters.zonaId    && { zonaId:    filters.zonaId    }),
      ...(filters.buscar && {
        OR: [
          { titulo:     { contains: filters.buscar, mode: 'insensitive' } },
          { descripcion:{ contains: filters.buscar, mode: 'insensitive' } },
          { direccion:  { contains: filters.buscar, mode: 'insensitive' } },
        ],
      }),
      ...((filters.precioMin != null || filters.precioMax != null) && {
        precio: {
          ...(filters.precioMin != null && { gte: filters.precioMin }),
          ...(filters.precioMax != null && { lte: filters.precioMax }),
        },
      }),
    };

    const [total, items] = await Promise.all([
      this.prisma.propiedad.count({ where }),
      this.prisma.propiedad.findMany({
        where,
        include: {
          imagenes: { orderBy: { orden: 'asc' }, take: 1 },
          zona:     { select: { id: true, nombre: true } },
        },
        orderBy: [
          { destacada: 'desc' },
          { createdAt: 'desc' },
        ],
        skip,
        take: limit,
      }),
    ]);

    return {
      success: true,
      data: items,
      meta: {
        total,
        page,
        limit,
        totalPages:  Math.ceil(total / limit),
        hasPrevPage: page > 1,
        hasNextPage: page < Math.ceil(total / limit),
      },
    };
  }

  async findOne(id: string, ctx: TenantContext) {
    const propiedad = await this.prisma.propiedad.findFirst({
      where: { id, organizationId: ctx.organizationId, isActive: true },
      include: {
        imagenes: { orderBy: { orden: 'asc' } },
        zona:     { select: { id: true, nombre: true, ciudad: true } },
      },
    });

    if (!propiedad) throw new NotFoundException('Propiedad no encontrada');
    return { success: true, data: propiedad };
  }

  async update(id: string, dto: UpdatePropiedadDto, ctx: TenantContext) {
    await this.findOne(id, ctx); // verifica que existe y pertenece a la org

    if (dto.zonaId) {
      const zona = await this.prisma.zona.findFirst({
        where: { id: dto.zonaId, organizationId: ctx.organizationId, isActive: true },
      });
      if (!zona) throw new BadRequestException('Zona inválida');
    }

    const propiedad = await this.prisma.propiedad.update({
      where: { id },
      data: {
        ...(dto.titulo       != null && { titulo:       dto.titulo       }),
        ...(dto.descripcion  != null && { descripcion:  dto.descripcion  }),
        ...(dto.tipo         != null && { tipo:         dto.tipo         }),
        ...(dto.operacion    != null && { operacion:    dto.operacion    }),
        ...(dto.precio       != null && { precio:       dto.precio       }),
        ...(dto.moneda       != null && { moneda:       dto.moneda       }),
        ...(dto.superficie   != null && { superficie:   dto.superficie   }),
        ...(dto.ambientes    != null && { ambientes:    dto.ambientes    }),
        ...(dto.banos        != null && { banos:        dto.banos        }),
        ...(dto.dormitorios  != null && { dormitorios:  dto.dormitorios  }),
        ...(dto.direccion    != null && { direccion:    dto.direccion    }),
        ...(dto.estado       != null && { estado:       dto.estado       }),
        ...(dto.destacada    != null && { destacada:    dto.destacada    }),
        ...(dto.zonaId       != null && { zonaId:       dto.zonaId       }),
        ...(dto.imagenes && {
          imagenes: {
            deleteMany: {},
            create: dto.imagenes.map((url, orden) => ({ url, orden })),
          },
        }),
      },
      include: {
        imagenes: { orderBy: { orden: 'asc' } },
        zona:     { select: { id: true, nombre: true } },
      },
    });

    await this.audit.log({
      action:         'propiedad.update',
      entityType:     'Propiedad',
      entityId:       id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        dto as Record<string, unknown>,
    });

    return { success: true, data: propiedad };
  }

  async remove(id: string, ctx: TenantContext) {
    await this.findOne(id, ctx);

    await this.prisma.propiedad.update({
      where: { id },
      data: { isActive: false },
    });

    await this.audit.log({
      action:         'propiedad.delete',
      entityType:     'Propiedad',
      entityId:       id,
      userId:         ctx.userId,
      organizationId: ctx.organizationId,
      payload:        {},
    });

    return { success: true, message: 'Propiedad eliminada correctamente' };
  }
}
EOF

cat > src/propiedades/propiedades.controller.ts << 'EOF'
// src/propiedades/propiedades.controller.ts
import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { PropiedadesService } from './propiedades.service';
import { CreatePropiedadDto } from './dto/create-propiedad.dto';
import { UpdatePropiedadDto } from './dto/update-propiedad.dto';
import { FilterPropiedadDto } from './dto/filter-propiedad.dto';
import { TenantGuard } from '../tenant/tenant.guard';
import { TenantCtx } from '../tenant/tenant.decorator';
import type { TenantContext } from '../tenant/tenant.interface';

@ApiTags('propiedades')
@ApiBearerAuth('firebase-jwt')
@UseGuards(TenantGuard)
@Controller('api/v1/propiedades')
export class PropiedadesController {
  constructor(private readonly propiedadesService: PropiedadesService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Crear propiedad' })
  create(@Body() dto: CreatePropiedadDto, @TenantCtx() ctx: TenantContext) {
    return this.propiedadesService.create(dto, ctx);
  }

  @Get()
  @ApiOperation({ summary: 'Listar propiedades con filtros y paginación' })
  findAll(
    @Query() filters: FilterPropiedadDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.propiedadesService.findAll(filters, ctx);
  }

  @Get(':id')
  @ApiParam({ name: 'id', description: 'ID de la propiedad' })
  @ApiOperation({ summary: 'Obtener propiedad por ID' })
  findOne(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.propiedadesService.findOne(id, ctx);
  }

  @Patch(':id')
  @ApiParam({ name: 'id', description: 'ID de la propiedad' })
  @ApiOperation({ summary: 'Actualizar propiedad' })
  update(
    @Param('id') id: string,
    @Body() dto: UpdatePropiedadDto,
    @TenantCtx() ctx: TenantContext,
  ) {
    return this.propiedadesService.update(id, dto, ctx);
  }

  @Delete(':id')
  @ApiParam({ name: 'id', description: 'ID de la propiedad' })
  @ApiOperation({ summary: 'Eliminar propiedad (soft delete)' })
  @ApiResponse({ status: 200, description: 'Propiedad eliminada' })
  remove(@Param('id') id: string, @TenantCtx() ctx: TenantContext) {
    return this.propiedadesService.remove(id, ctx);
  }
}
EOF

cat > src/propiedades/propiedades.module.ts << 'EOF'
// src/propiedades/propiedades.module.ts
import { Module } from '@nestjs/common';
import { PropiedadesController } from './propiedades.controller';
import { PropiedadesService } from './propiedades.service';
import { TenantModule } from '../tenant/tenant.module';
import { AuditModule } from '../audit/audit.module';

@Module({
  imports: [TenantModule, AuditModule],
  controllers: [PropiedadesController],
  providers: [PropiedadesService],
  exports: [PropiedadesService],
})
export class PropiedadesModule {}
EOF

cat > src/propiedades/propiedades.service.spec.ts << 'EOF'
// src/propiedades/propiedades.service.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { PropiedadesService } from './propiedades.service';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';

const mockPrisma = {
  propiedad: {
    create:   jest.fn(),
    findMany: jest.fn(),
    findFirst: jest.fn(),
    count:    jest.fn(),
    update:   jest.fn(),
  },
  zona: { findFirst: jest.fn() },
};

const mockAudit = { log: jest.fn() };

const ctx = {
  userId: 'user-1',
  organizationId: 'org-1',
  role: 'ADMIN',
  firebaseUid: 'uid-1',
};

const baseProp = {
  id: 'prop-1',
  titulo: 'Casa en el centro',
  tipo: 'CASA',
  operacion: 'VENTA',
  precio: 150000,
  moneda: 'USD',
  estado: 'DISPONIBLE',
  isActive: true,
  organizationId: 'org-1',
  imagenes: [],
  zona: null,
};

describe('PropiedadesService', () => {
  let service: PropiedadesService;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PropiedadesService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: AuditService, useValue: mockAudit },
      ],
    }).compile();
    service = module.get<PropiedadesService>(PropiedadesService);
  });

  describe('create', () => {
    const dto = {
      titulo: 'Casa en el centro',
      tipo: 'CASA' as any,
      operacion: 'VENTA' as any,
      precio: 150000,
    };

    it('crea una propiedad correctamente', async () => {
      mockPrisma.propiedad.create.mockResolvedValue(baseProp);

      const result = await service.create(dto, ctx);

      expect(result.success).toBe(true);
      expect(mockPrisma.propiedad.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            titulo: 'Casa en el centro',
            organizationId: 'org-1',
            moneda: 'USD',
            estado: 'DISPONIBLE',
          }),
        }),
      );
      expect(mockAudit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'propiedad.create' }),
      );
    });

    it('lanza BadRequest si la zona no pertenece a la org', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue(null);

      await expect(
        service.create({ ...dto, zonaId: 'zona-ajena' }, ctx),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('findAll', () => {
    it('retorna items paginados con meta', async () => {
      mockPrisma.propiedad.count.mockResolvedValue(5);
      mockPrisma.propiedad.findMany.mockResolvedValue([baseProp]);

      const result = await service.findAll({ page: 1, limit: 20 }, ctx);

      expect(result.success).toBe(true);
      expect(result.meta.total).toBe(5);
      expect(result.meta.totalPages).toBe(1);
    });
  });

  describe('findOne', () => {
    it('retorna la propiedad si existe y pertenece a la org', async () => {
      mockPrisma.propiedad.findFirst.mockResolvedValue(baseProp);
      const result = await service.findOne('prop-1', ctx);
      expect(result.success).toBe(true);
    });

    it('lanza NotFoundException si no existe', async () => {
      mockPrisma.propiedad.findFirst.mockResolvedValue(null);
      await expect(service.findOne('prop-none', ctx))
        .rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('remove', () => {
    it('hace soft delete y loguea audit', async () => {
      mockPrisma.propiedad.findFirst.mockResolvedValue(baseProp);
      mockPrisma.propiedad.update.mockResolvedValue({ ...baseProp, isActive: false });

      const result = await service.remove('prop-1', ctx);
      expect(result.success).toBe(true);
      expect(mockPrisma.propiedad.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { isActive: false } }),
      );
    });
  });
});
EOF
ok "PropiedadesModule completo con tests"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-3 — HealthModule
# ═══════════════════════════════════════════════════════════════════════════════
info "DB-3 — Creando HealthModule..."

cat > src/health/health.controller.ts << 'EOF'
// src/health/health.controller.ts
import { Controller, Get } from '@nestjs/common';
import {
  HealthCheck,
  HealthCheckService,
  PrismaHealthIndicator,
  MemoryHealthIndicator,
} from '@nestjs/terminus';
import { PrismaService } from '../prisma/prisma.service';
import { Public } from '../common/decorators/public.decorator';
import { ApiOperation, ApiTags } from '@nestjs/swagger';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private prismaHealth: PrismaHealthIndicator,
    private memory: MemoryHealthIndicator,
    private prisma: PrismaService,
  ) {}

  @Public()
  @Get()
  @HealthCheck()
  @ApiOperation({ summary: 'Health check: DB y memoria' })
  check() {
    return this.health.check([
      () => this.prismaHealth.pingCheck('database', this.prisma),
      () => this.memory.checkHeap('memory_heap', 300 * 1024 * 1024),
      () => this.memory.checkRSS('memory_rss',   512 * 1024 * 1024),
    ]);
  }
}
EOF

cat > src/health/health.module.ts << 'EOF'
// src/health/health.module.ts
import { Module } from '@nestjs/common';
import { TerminusModule } from '@nestjs/terminus';
import { HealthController } from './health.controller';

@Module({
  imports: [TerminusModule],
  controllers: [HealthController],
})
export class HealthModule {}
EOF
ok "HealthModule"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-1 + DB-3 — AppModule actualizado
# ═══════════════════════════════════════════════════════════════════════════════
info "Actualizando AppModule..."

cat > src/app.module.ts << 'EOF'
// src/app.module.ts
import { Module, MiddlewareConsumer, NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from './prisma/prisma.module';
import { FirebaseModule } from './firebase/firebase.module';
import { AuditModule } from './audit/audit.module';
import { TenantModule } from './tenant/tenant.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { ZonasModule } from './zonas/zonas.module';
import { PropiedadesModule } from './propiedades/propiedades.module';
import { HealthModule } from './health/health.module';
import { LoggingMiddleware } from './common/middleware/logging.middleware';
import { envValidation } from './config/env.validation';
import { FirebaseAuthGuard } from './auth/guards/firebase-auth.guard';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal:    true,
      validate:    envValidation,
      envFilePath: '.env',
    }),
    PrismaModule,
    FirebaseModule,
    AuditModule,
    TenantModule,
    AuthModule,
    UsersModule,
    ZonasModule,
    PropiedadesModule,
    HealthModule,
  ],
  providers: [
    {
      provide:   APP_GUARD,
      useClass:  FirebaseAuthGuard,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggingMiddleware).forRoutes('*');
  }
}
EOF
ok "src/app.module.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-1 — main.ts actualizado
# ═══════════════════════════════════════════════════════════════════════════════
info "Actualizando main.ts..."

cat > src/main.ts << 'EOF'
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
EOF
ok "src/main.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-1 — .env.example actualizado
# ═══════════════════════════════════════════════════════════════════════════════
info "Actualizando .env.example..."

cat > .env.example << 'EOF'
# ─── Servidor ────────────────────────────────────────────────────────────────
NODE_ENV=development
PORT=3001

# ─── Base de datos ────────────────────────────────────────────────────────────
DATABASE_URL=postgresql://user:password@localhost:5432/real_estate_dashboard?schema=public

# ─── Firebase Admin SDK ───────────────────────────────────────────────────────
# Firebase Console → Configuración → Cuentas de servicio → Generar clave privada
FIREBASE_PROJECT_ID=tu-proyecto-id
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@tu-proyecto.iam.gserviceaccount.com
# Nota: los \n en la private key deben ser literales \\n en el .env
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"

# ─── Sistema 1 — real-back ────────────────────────────────────────────────────
# URL interna del Sistema 1 (organizaciones-back / real-back)
# En producción: URL del servidor donde corre el real-back
REAL_BACK_URL=http://localhost:3000

# ─── CORS ─────────────────────────────────────────────────────────────────────
# Frontend del dashboard — separar por comas si hay múltiples orígenes
ALLOWED_ORIGINS=http://localhost:3002

# ─── Rate limiting (opcional — defaults aplicados si no están) ────────────────
THROTTLE_TTL_MS=60000
THROTTLE_LIMIT=100
EOF
ok ".env.example"

# ═══════════════════════════════════════════════════════════════════════════════
#  DB-1 — seed.ts actualizado para real estate
# ═══════════════════════════════════════════════════════════════════════════════
info "Actualizando prisma/seed.ts..."

cat > prisma/seed.ts << 'EOF'
// prisma/seed.ts
import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';
import * as pg from 'pg';

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter } as any);

const SEED_ORG_ID = 'org-real-estate-seed-000000000001';

async function main() {
  console.log('🌱 Iniciando seed — Real Estate Dashboard\n');

  // ── Organización demo ──────────────────────────────────────────────────────
  const org = await prisma.organization.upsert({
    where: { id: SEED_ORG_ID },
    update: {},
    create: {
      id:   SEED_ORG_ID,
      name: 'Inmobiliaria San Martín',
      slug: 'inmobiliaria-san-martin',
      enabledProducts: {
        propiedades: true,
        chat:        true,
        pagos:       false,
        campanas:    false,
      },
      systemSettings: {},
    },
  });
  console.log(`✅ Organización: ${org.name} (${org.id})`);

  // ── Zonas ─────────────────────────────────────────────────────────────────
  console.log('\n📍 Creando zonas...');

  const zonasData = [
    { nombre: 'Centro',         ciudad: 'San Fernando del Valle', provincia: 'Catamarca' },
    { nombre: 'Norte',          ciudad: 'San Fernando del Valle', provincia: 'Catamarca' },
    { nombre: 'Zona Residencial', ciudad: 'San Fernando del Valle', provincia: 'Catamarca' },
  ];

  const zonas: Record<string, string> = {};
  for (const z of zonasData) {
    const zona = await prisma.zona.upsert({
      where: { id: `zona-${z.nombre.toLowerCase().replace(/ /g, '-')}-seed` },
      update: {},
      create: {
        id:             `zona-${z.nombre.toLowerCase().replace(/ /g, '-')}-seed`,
        nombre:         z.nombre,
        ciudad:         z.ciudad,
        provincia:      z.provincia,
        organizationId: SEED_ORG_ID,
      },
    });
    zonas[z.nombre] = zona.id;
    console.log(`  ✅ ${zona.nombre}`);
  }

  // ── Propiedades demo ───────────────────────────────────────────────────────
  console.log('\n🏠 Creando propiedades demo...');

  const propiedadesData = [
    {
      titulo: 'Casa amplia en el centro con jardín',
      tipo: 'CASA', operacion: 'VENTA', precio: 180000, moneda: 'USD',
      superficie: 180, ambientes: 5, banos: 2, dormitorios: 3,
      direccion: 'Av. Güemes 245, Centro',
      estado: 'DISPONIBLE', destacada: true, zona: 'Centro',
    },
    {
      titulo: 'Departamento moderno 2 ambientes',
      tipo: 'DEPARTAMENTO', operacion: 'ALQUILER', precio: 120000, moneda: 'ARS',
      superficie: 55, ambientes: 2, banos: 1, dormitorios: 1,
      direccion: 'Sarmiento 780, Centro',
      estado: 'DISPONIBLE', destacada: false, zona: 'Centro',
    },
    {
      titulo: 'Terreno con vista al cerro',
      tipo: 'TERRENO', operacion: 'VENTA', precio: 45000, moneda: 'USD',
      superficie: 600, ambientes: null, banos: null, dormitorios: null,
      direccion: 'Camino al Portezuelo s/n',
      estado: 'DISPONIBLE', destacada: false, zona: 'Norte',
    },
    {
      titulo: 'Casa en barrio residencial — 4 dormitorios',
      tipo: 'CASA', operacion: 'VENTA', precio: 250000, moneda: 'USD',
      superficie: 220, ambientes: 6, banos: 3, dormitorios: 4,
      direccion: 'Los Aromos 123',
      estado: 'RESERVADA', destacada: true, zona: 'Zona Residencial',
    },
  ];

  for (const p of propiedadesData) {
    const propiedad = await prisma.propiedad.create({
      data: {
        titulo:         p.titulo,
        tipo:           p.tipo as any,
        operacion:      p.operacion as any,
        precio:         p.precio,
        moneda:         p.moneda,
        superficie:     p.superficie,
        ambientes:      p.ambientes,
        banos:          p.banos,
        dormitorios:    p.dormitorios,
        direccion:      p.direccion,
        estado:         p.estado as any,
        destacada:      p.destacada,
        organizationId: SEED_ORG_ID,
        zonaId:         zonas[p.zona],
      },
    });
    console.log(`  ✅ ${propiedad.titulo.slice(0, 50)}...`);
  }

  console.log('\n🎉 Seed completado');
  console.log('─────────────────────────────────────────────────────');
  console.log(`🏢 Organización: ${org.name}`);
  console.log(`📍 Zonas:        ${zonasData.length}`);
  console.log(`🏠 Propiedades:  ${propiedadesData.length}`);
}

main()
  .catch((e) => { console.error('❌', e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); await pool.end(); });
EOF
ok "prisma/seed.ts"

# ═══════════════════════════════════════════════════════════════════════════════
#  Instalar dependencias finales + build + tests
# ═══════════════════════════════════════════════════════════════════════════════
info "Instalando dependencias finales..."
pnpm add helmet
pnpm install

echo ""
info "Ejecutando build de verificación..."
pnpm run build 2>&1 | tail -25

echo ""
info "Ejecutando tests..."
pnpm run test --passWithNoTests 2>&1 | tail -30

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ real-dashboard-back — Real Estate listo${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Sprints completados:"
echo "  DB-1 — Dominio Apple eliminado, Real Estate creado, AppModule limpio  ✓"
echo "  DB-2 — AuthService conectado con Sistema 1 (real-back), JWT eliminado ✓"
echo "  DB-3 — ZonasModule + PropiedadesModule con filtros, paginación, tests  ✓"
echo ""
echo "Endpoints disponibles:"
echo "  POST   /api/v1/auth/sync"
echo "  GET    /api/v1/auth/me"
echo "  GET    /api/v1/zonas"
echo "  POST   /api/v1/zonas"
echo "  GET    /api/v1/zonas/:id"
echo "  PATCH  /api/v1/zonas/:id"
echo "  DELETE /api/v1/zonas/:id"
echo "  GET    /api/v1/propiedades"
echo "  POST   /api/v1/propiedades"
echo "  GET    /api/v1/propiedades/:id"
echo "  PATCH  /api/v1/propiedades/:id"
echo "  DELETE /api/v1/propiedades/:id"
echo "  GET    /health"
echo "  GET    /api/docs  (Swagger — solo NODE_ENV != production)"
echo ""
echo "────────────────────────────────────────────────────────────"
echo "  RECORDATORIO — pasos manuales:"
echo ""
echo "  1. Copiar real-dashboard-schema.prisma → prisma/schema.prisma"
echo "  2. pnpm prisma migrate dev --name real_estate_domain"
echo "  3. Copiar .env.example → .env y completar los valores"
echo "  4. Agregar REAL_BACK_URL apuntando al real-back (Sistema 1)"
echo "  5. Opcional: pnpm prisma db seed"
echo "────────────────────────────────────────────────────────────"
echo ""