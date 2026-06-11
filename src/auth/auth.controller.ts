// src/auth/auth.controller.ts
import {
  Controller,
  Post,
  Get,
  Body,
  Req,
  Res,
  HttpCode,
  HttpStatus,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
} from '@nestjs/swagger';
import { AuthService }        from './auth.service';
import { FirebaseAuthGuard }  from './guards/firebase-auth.guard';
import { FirebaseSsoDto }     from './dto/firebase-sso.dto';
import { SyncAuthDto }        from './dto/sync-auth.dto';
import { RefreshTokenDto }    from './dto/refresh-token.dto';
import { Public }             from '../common/decorators/public.decorator';
import { CurrentUser }        from '../common/decorators/current-user.decorator';

// ─── Helpers de cookie ────────────────────────────────────────────────────────

const IS_PROD = process.env.NODE_ENV === 'production';

/**
 * Escribe access_token y refresh_token como cookies HttpOnly.
 * SameSite=None; Secure es requerido para cross-domain (Railway subdominios).
 */
function setAuthCookies(res: Response, accessToken: string, refreshToken: string): void {
  const base = {
    httpOnly: true,
    secure:   IS_PROD,           // solo HTTPS en producción
    sameSite: IS_PROD            // cross-domain en prod, lax en dev
      ? ('none' as const)
      : ('lax'  as const),
    path: '/',
  };

  res.cookie('access_token', accessToken, {
    ...base,
    maxAge: 15 * 60 * 1000,      // 15 minutos
  });

  res.cookie('refresh_token', refreshToken, {
    ...base,
    maxAge: 7 * 24 * 60 * 60 * 1000,  // 7 días
    path:   '/api/v1/auth/refresh',    // solo accesible en el endpoint de refresh
  });
}

function clearAuthCookies(res: Response): void {
  const opts = {
    httpOnly: true,
    secure:   IS_PROD,
    sameSite: IS_PROD ? ('none' as const) : ('lax' as const),
  };
  res.clearCookie('access_token',  { ...opts, path: '/' });
  res.clearCookie('refresh_token', { ...opts, path: '/api/v1/auth/refresh' });
}

// ─── Controller ───────────────────────────────────────────────────────────────

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /**
   * POST /api/v1/auth/firebase-sso
   * Intercambia un Firebase ID Token por JWT propio del dashboard.
   * Escribe los tokens como cookies HttpOnly (cross-domain) Y los devuelve
   * en el body para compatibilidad con clientes que usan localStorage.
   */
  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'SSO con Firebase ID Token → JWT propio' })
  @ApiResponse({ status: 200, description: 'Login exitoso' })
  @ApiResponse({ status: 401, description: 'Token Firebase inválido' })
  async firebaseSso(
    @Body() dto: FirebaseSsoDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result = await this.authService.firebaseSso(dto);
    // Escribir cookies HttpOnly para el browser
    setAuthCookies(res, result.accessToken, result.refreshToken);
    // Devolver también en body (compatibilidad con código que lee localStorage)
    return result;
  }

  /**
   * POST /api/v1/auth/sync
   * Crea o actualiza el usuario en la DB del dashboard.
   * Requiere Firebase token en Authorization header.
   */
  @UseGuards(FirebaseAuthGuard)
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  @ApiBearerAuth('firebase-jwt')
  @ApiOperation({ summary: 'Sincronizar usuario con Firebase' })
  async sync(
    @Body() dto: SyncAuthDto,
    @CurrentUser() currentUser: { uid: string; email: string },
  ) {
    return this.authService.sync({
      ...dto,
      firebaseUid: currentUser.uid,
      email:       dto.email || currentUser.email,
    });
  }

  /**
   * GET /api/v1/auth/me
   * Retorna el perfil del usuario autenticado.
   * Acepta JWT en Authorization header O en cookie access_token.
   */
  @UseGuards(FirebaseAuthGuard)
  @Get('me')
  @ApiBearerAuth('firebase-jwt')
  @ApiOperation({ summary: 'Perfil del usuario autenticado' })
  async me(@CurrentUser() currentUser: { uid: string }) {
    return this.authService.me(currentUser.uid);
  }

  /**
   * POST /api/v1/auth/refresh
   * Renueva el access token usando el refresh token.
   * Lee el refresh_token de la cookie O del body.
   */
  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Renovar access token' })
  async refresh(
    @Body() dto: RefreshTokenDto,
    @Req()  req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    // Preferir cookie sobre body
    const refreshToken = (req.cookies?.['refresh_token'] as string | undefined)
      ?? dto.refreshToken;

    const result = await this.authService.refresh({ refreshToken });
    setAuthCookies(res, result.accessToken, result.refreshToken);
    return result;
  }

  /**
   * POST /api/v1/auth/logout
   * Limpia las cookies de auth.
   */
  @Public()
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Cerrar sesión' })
  logout(@Res({ passthrough: true }) res: Response) {
    clearAuthCookies(res);
    return { success: true, message: 'Sesión cerrada' };
  }
}
