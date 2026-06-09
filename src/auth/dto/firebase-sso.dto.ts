// src/auth/dto/firebase-sso.dto.ts
import { IsString, IsNotEmpty } from 'class-validator';

export class FirebaseSsoDto {
  @IsString()
  @IsNotEmpty()
  firebaseIdToken: string;
}
