// src/auth/auth.service.ts
import { Injectable, NotFoundException, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { SyncAuthDto } from './dto/sync-auth.dto';
import { AuditService } from '../audit/audit.service';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /**
   * POST /api/v1/auth/sync
   * Upsert del usuario en base al firebaseUid.
   * Se llama desde el frontend justo después de que Firebase emite un ID token.
   */
  async sync(dto: SyncAuthDto) {
    const user = await this.prisma.user.upsert({
      where: { firebaseUid: dto.firebaseUid },
      create: {
        firebaseUid: dto.firebaseUid,
        firebaseEmail: dto.email,
        email: dto.email,
        nombre: dto.nombre ?? dto.email.split('@')[0],
        role: 'VENDEDOR',
      },
      update: {
        firebaseEmail: dto.email,
        email: dto.email,
        ...(dto.nombre && { nombre: dto.nombre }),
      },
      select: {
        id: true,
        email: true,
        nombre: true,
        role: true,
        firebaseUid: true,
        isActive: true,
        createdAt: true,
      },
    });

    await this.audit.log({
      action: 'auth.sync',
      entityType: 'User',
      entityId: user.id,
      userId: user.id,
      payload: { email: dto.email },
    });

    return user;
  }

  /**
   * GET /api/v1/auth/me
   * Retorna el perfil del usuario autenticado.
   */
  async me(firebaseUid: string) {
    const user = await this.prisma.user.findUnique({
      where: { firebaseUid },
      select: {
        id: true,
        email: true,
        nombre: true,
        role: true,
        firebaseUid: true,
        isActive: true,
        createdAt: true,
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
