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
import { Public } from '../common/decorators/public.decorator';
import type { Request as ExpressRequest } from 'express';

@Controller('api/v1/auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /**
   * POST /api/v1/auth/sync
   * Público — el ID token de Firebase se valida en el guard a nivel global.
   * El frontend llama este endpoint justo después del login de Firebase.
   */
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  sync(@Body() dto: SyncAuthDto) {
    return this.authService.sync(dto);
  }

  /**
   * GET /api/v1/auth/me
   * Protegido por FirebaseAuthGuard (global).
   */
  @Get('me')
  me(@Request() req: ExpressRequest) {
    const firebaseUid = (req as any).user?.firebaseUid as string;
    return this.authService.me(firebaseUid);
  }
}
