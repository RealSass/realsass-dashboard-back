// src/auth/dto/firebase-sso.dto.ts
import { IsString, IsNotEmpty } from 'class-validator';

export class FirebaseSsoDto {
  /** Firebase ID token obtenido con firebaseUser.getIdToken() */
  @IsString()
  @IsNotEmpty()
  firebaseIdToken: string;
}
