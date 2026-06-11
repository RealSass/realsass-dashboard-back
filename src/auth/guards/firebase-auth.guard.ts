// src/auth/guards/firebase-auth.guard.ts
//
// Cookie access_token  → JWT propio  → JwtService.verify()
// Header Authorization → Firebase ID token → firebase.auth().verifyIdToken()
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Inject,
  Logger,
} from '@nestjs/common';
import { Reflector }     from '@nestjs/core';
import { JwtService }    from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import type { Request }  from 'express';
import type * as admin   from 'firebase-admin';
import { FIREBASE_ADMIN } from '../../firebase/firebase.module';

export const IS_PUBLIC_KEY = 'isPublic';

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  private readonly logger = new Logger(FirebaseAuthGuard.name);

  constructor(
    @Inject(FIREBASE_ADMIN) private readonly firebase: admin.app.App | null,
    private readonly reflector: Reflector,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const { token, source } = this.extractToken(request);

    if (!token) throw new UnauthorizedException('Token de autenticación requerido');

    return source === 'cookie'
      ? this.verifyJwt(token, request)
      : this.verifyFirebase(token, request);
  }

  private verifyJwt(token: string, request: Request): boolean {
    try {
      const secret = this.configService.get<string>('JWT_ACCESS_SECRET', 'change_me_access');
      const payload = this.jwtService.verify(token, { secret }) as {
        sub: string; email: string; nombre: string; role: string;
      };
      (request as any).user = {
        uid:         payload.sub,
        email:       payload.email,
        firebaseUid: payload.sub,
        nombre:      payload.nombre,
        role:        payload.role,
      };
      return true;
    } catch (err) {
      this.logger.warn(`JWT inválido: ${(err as Error).message}`);
      throw new UnauthorizedException('Token inválido o expirado');
    }
  }

  private async verifyFirebase(token: string, request: Request): Promise<boolean> {
    if (!this.firebase) throw new UnauthorizedException('Firebase no configurado');
    try {
      const decoded = await this.firebase.auth().verifyIdToken(token, true);
      (request as any).user = {
        uid:         decoded.uid,
        email:       decoded.email ?? '',
        firebaseUid: decoded.uid,
      };
      return true;
    } catch (err) {
      this.logger.warn(`Firebase token inválido: ${(err as Error).message}`);
      throw new UnauthorizedException('Token inválido o expirado');
    }
  }

  private extractToken(request: Request): { token: string | null; source: 'cookie' | 'header' } {
    const cookie = (request.cookies as Record<string, string> | undefined)?.['access_token'];
    if (cookie) return { token: cookie, source: 'cookie' };

    const [type, token] = request.headers.authorization?.split(' ') ?? [];
    if (type === 'Bearer' && token) return { token, source: 'header' };

    return { token: null, source: 'header' };
  }
}
