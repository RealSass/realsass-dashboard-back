// src/auth/dto/sync-auth.dto.ts
import { IsEmail, IsOptional, IsString } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class SyncAuthDto {
  @ApiProperty({ description: 'Firebase UID del usuario' })
  @IsString()
  firebaseUid: string;

  @ApiProperty({ description: 'Email del usuario' })
  @IsEmail()
  email: string;

  @ApiPropertyOptional({ description: 'Nombre visible del usuario' })
  @IsOptional()
  @IsString()
  nombre?: string;

  @ApiPropertyOptional({ description: 'URL del avatar del usuario' })
  @IsOptional()
  @IsString()
  avatarUrl?: string;
}
