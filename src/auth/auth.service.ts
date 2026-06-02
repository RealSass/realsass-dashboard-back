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
