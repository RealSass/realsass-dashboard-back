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
import { RefreshTokenDto } from './dto/refresh-token.dto';

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

    let decoded: admin.auth.DecodedIdToken;
    try {
      decoded = await this.firebase.auth().verifyIdToken(dto.firebaseIdToken, true);
    } catch (err) {
      this.logger.warn(`SSO token inválido: ${(err as Error).message}`);
      throw new UnauthorizedException('Token de Firebase inválido o expirado');
    }

    const uid   = decoded.uid;
    const email = decoded.email ?? '';

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

    if (!user.isActive) {
      throw new ForbiddenException('Cuenta desactivada. Contactá al administrador.');
    }

    const payload = { sub: user.id, email: user.email, nombre: user.nombre, role: user.role };

    const accessToken = this.jwtService.sign(payload, {
      secret:    process.env['JWT_ACCESS_SECRET']     ?? 'change_me_access',
      expiresIn: (process.env['JWT_ACCESS_EXPIRES_IN'] ?? '15m') as any,
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret:    process.env['JWT_REFRESH_SECRET']     ?? 'change_me_refresh',
      expiresIn: (process.env['JWT_REFRESH_EXPIRES_IN'] ?? '7d') as any,
    });

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

    return { accessToken, refreshToken, user: { id: user.id, email: user.email, nombre: user.nombre, role: user.role } };
  }

  /**
   * POST /api/v1/auth/refresh
   * El dashboard-front llama este endpoint cuando el accessToken expira.
   * Verifica el refreshToken, emite un nuevo par de tokens.
   */
  async refresh(dto: RefreshTokenDto): Promise<{
    accessToken:  string;
    refreshToken: string;
  }> {
    // 1. Verificar que el refreshToken sea válido
    let payload: { sub: string; email: string; nombre?: string; role: string };
    try {
      payload = this.jwtService.verify(dto.refreshToken, {
        secret: process.env['JWT_REFRESH_SECRET'] ?? 'change_me_refresh',
      });
    } catch {
      throw new UnauthorizedException('Refresh token inválido o expirado');
    }

    // 2. Verificar que el usuario exista y el token coincida en DB
    const user = await this.prisma.user.findFirst({
      where:  { id: payload.sub, refreshToken: dto.refreshToken },
      select: { id: true, email: true, nombre: true, role: true, isActive: true },
    });

    if (!user) {
      throw new UnauthorizedException('Refresh token revocado o usuario no encontrado');
    }

    if (!user.isActive) {
      throw new ForbiddenException('Cuenta desactivada.');
    }

    // 3. Emitir nuevos tokens
    const newPayload = { sub: user.id, email: user.email, nombre: user.nombre, role: user.role };

    const accessToken = this.jwtService.sign(newPayload, {
      secret:    process.env['JWT_ACCESS_SECRET']     ?? 'change_me_access',
      expiresIn: (process.env['JWT_ACCESS_EXPIRES_IN'] ?? '15m') as any,
    });

    const refreshToken = this.jwtService.sign(newPayload, {
      secret:    process.env['JWT_REFRESH_SECRET']     ?? 'change_me_refresh',
      expiresIn: (process.env['JWT_REFRESH_EXPIRES_IN'] ?? '7d') as any,
    });

    // 4. Rotar el refresh token en DB
    await this.prisma.user.update({
      where: { id: user.id },
      data:  { refreshToken },
    });

    return { accessToken, refreshToken };
  }
}
