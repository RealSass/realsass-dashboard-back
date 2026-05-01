// src/auth/dto/sync-auth.dto.ts
import { IsEmail, IsOptional, IsString } from 'class-validator';

export class SyncAuthDto {
  @IsString()
  firebaseUid: string;

  @IsEmail()
  email: string;

  @IsOptional()
  @IsString()
  nombre?: string;
}
