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
import { JwtService } from '@nestjs/jwt';
import { FIREBASE_ADMIN } from '../firebase/firebase.module';
import type * as admin from 'firebase-admin';
import { FirebaseSsoDto } from './dto/firebase-sso.dto';
import { JwtService } from '@nestjs/jwt';
import { FIREBASE_ADMIN } from '../firebase/firebase.module';
import type * as admin from 'firebase-admin';
import { FirebaseSsoDto } from './dto/firebase-sso.dto';
import { SyncAuthDto } from './dto/sync-auth.dto';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly realBackUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly jwtService: JwtService,
    @Inject(FIREBASE_ADMIN) private readonly firebase: admin.app.App | null,
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
