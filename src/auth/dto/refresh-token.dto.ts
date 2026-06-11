// src/auth/dto/refresh-token.dto.ts
import { IsString, IsOptional } from 'class-validator';

export class RefreshTokenDto {
  // Opcional: viene de cookie HttpOnly O del body como fallback
  @IsString()
  @IsOptional()
  refreshToken?: string;
}
