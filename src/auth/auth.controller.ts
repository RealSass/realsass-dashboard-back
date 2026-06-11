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
import { AuthService }       from './auth.service';
import { FirebaseAuthGuard } from './guards/firebase-auth.guard';
import { FirebaseSsoDto }    from './dto/firebase-sso.dto';
import { SyncAuthDto }       from './dto/sync-auth.dto';
import { RefreshTokenDto }   from './dto/refresh-token.dto';
import { Public }            from '../common/decorators/public.decorator';
import { CurrentUser }       from '../common/decorators/current-user.decorator';

const IS_PROD = process.env.NODE_ENV === 'production';

function setAuthCookies(res: Response, accessToken: string, refreshToken: string): void {
  const base = {
    httpOnly: true,
    secure:   IS_PROD,
    sameSite: IS_PROD ? ('none' as const) : ('lax' as const),
  };

  res.cookie('access_token', accessToken, {
    ...base,
    path:   '/',
    maxAge: 15 * 60 * 1000,
  });

  res.cookie('refresh_token', refreshToken, {
    ...base,
    path:   '/api/v1/auth/refresh',
    maxAge: 7 * 24 * 60 * 60 * 1000,
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

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'SSO con Firebase ID Token → JWT + cookies' })
  @ApiResponse({ status: 200, description: 'Login exitoso' })
  async firebaseSso(
    @Body() dto: FirebaseSsoDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result = await this.authService.firebaseSso(dto);
    setAuthCookies(res, result.accessToken, result.refreshToken);
    return result;
  }

  @UseGuards(FirebaseAuthGuard)
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  @ApiBearerAuth('firebase-jwt')
  @ApiOperation({ summary: 'Sincronizar usuario con Firebase' })
  async sync(
    @Body() dto: SyncAuthDto,
    @CurrentUser() cu: { uid: string; email: string },
  ) {
    return this.authService.sync({ ...dto, firebaseUid: cu.uid, email: dto.email || cu.email });
  }

  @UseGuards(FirebaseAuthGuard)
  @Get('me')
  @ApiBearerAuth('firebase-jwt')
  @ApiOperation({ summary: 'Perfil del usuario autenticado' })
  async me(@CurrentUser() cu: { uid: string }) {
    return this.authService.me(cu.uid);
  }

  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Renovar access token' })
  async refresh(
    @Body() dto: RefreshTokenDto,
    @Req()  req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const refreshToken =
      (req.cookies as Record<string, string> | undefined)?.['refresh_token']
      ?? dto.refreshToken;

    const result = await this.authService.refresh({ refreshToken });
    setAuthCookies(res, result.accessToken, result.refreshToken);
    return result;
  }

  @Public()
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Cerrar sesión' })
  logout(@Res({ passthrough: true }) res: Response) {
    clearAuthCookies(res);
    return { success: true, message: 'Sesión cerrada' };
  }
}
