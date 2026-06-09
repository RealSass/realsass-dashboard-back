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
import { RefreshTokenDto } from './dto/refresh-token.dto';
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

  /** POST /api/v1/auth/firebase-sso */
  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  firebaseSso(@Body() dto: FirebaseSsoDto) {
    return this.authService.firebaseSso(dto);
  }

  /**
   * POST /api/v1/auth/refresh
   * Ruta pública. El dashboard-front renueva tokens cuando expira el accessToken.
   */
  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@Body() dto: RefreshTokenDto) {
    return this.authService.refresh(dto);
  }
}
