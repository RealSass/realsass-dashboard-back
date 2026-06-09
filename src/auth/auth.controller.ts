// src/auth/auth.controller.ts
import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Req,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { Request } from 'express';
import { AuthService } from './auth.service';
import { SyncAuthDto } from './dto/sync-auth.dto';
import { FirebaseSsoDto } from './dto/firebase-sso.dto';

@ApiTags('auth')
@ApiBearerAuth('firebase-jwt')
@Controller('api/v1/auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /**
   * POST /api/v1/auth/sync
   * Sincroniza usuario Firebase con la DB del dashboard
   * y obtiene el perfil del Sistema 1 (real-back).
   */
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Sincroniza usuario con DB local y Sistema 1' })
  @ApiResponse({ status: 200, description: 'Usuario sincronizado' })
  @ApiResponse({ status: 401, description: 'Token inválido' })
  async sync(@Body() dto: SyncAuthDto, @Req() req: Request) {
    // Extraer el token original para reusarlo en la llamada al Sistema 1
    const token = req.headers.authorization?.split(' ')[1] ?? '';
    const result = await this.authService.sync(dto, token);
    return { success: true, data: result };
  }

  /**
   * GET /api/v1/auth/me
   * Retorna el perfil del usuario autenticado en el dashboard.
   */
  @Get('me')
  @ApiOperation({ summary: 'Perfil del usuario autenticado' })
  @ApiResponse({ status: 200, description: 'Perfil del usuario' })
  async me(@Req() req: Request) {
    const firebaseUid = (req as any).user?.firebaseUid as string;
    const user = await this.authService.me(firebaseUid);
    return { success: true, data: user };
  }

  /**
   * POST /api/v1/auth/firebase-sso
   * Ruta pública. Recibe Firebase ID token de real-front y devuelve
   * accessToken + refreshToken del sistema dashboard.
   */
  @Public()
  @Post('firebase-sso')
  @HttpCode(HttpStatus.OK)
  firebaseSso(@Body() dto: FirebaseSsoDto) {
    return this.authService.firebaseSso(dto);
  }
}
