// src/auth/guards/firebase-auth.guard.ts
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Inject,
  Logger,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import type * as admin from 'firebase-admin';
import { FIREBASE_ADMIN } from '../../firebase/firebase.module';

export const IS_PUBLIC_KEY = 'isPublic';

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  private readonly logger = new Logger(FirebaseAuthGuard.name);

  constructor(
    @Inject(FIREBASE_ADMIN) private readonly firebase: admin.app.App | null,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    // Rutas marcadas con @Public() pasan sin auth
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const token = this.extractToken(request);

    if (!token) {
      throw new UnauthorizedException('Token de autenticación requerido');
    }

    if (!this.firebase) {
      throw new UnauthorizedException('Firebase no configurado en este entorno');
    }

    try {
      const decoded = await this.firebase.auth().verifyIdToken(token, true);
      // Inyectar el decoded token en el request para uso posterior
      (request as any).firebaseUser = decoded;
      (request as any).user = {
        uid: decoded.uid,
        email: decoded.email ?? '',
        firebaseUid: decoded.uid,
      };
      return true;
    } catch (err) {
      this.logger.warn(`Token inválido: ${(err as Error).message}`);
      throw new UnauthorizedException('Token inválido o expirado');
    }
  }

  private extractToken(request: Request): string | null {
    const [type, token] = request.headers.authorization?.split(' ') ?? [];
    return type === 'Bearer' && token ? token : null;
  }
}
