// src/auth/auth.module.ts
import { Module }        from '@nestjs/common';
import { JwtModule }     from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { AuthController }  from './auth.controller';
import { AuthService }     from './auth.service';
import { FirebaseAuthGuard } from './guards/firebase-auth.guard';
import { AuditModule }     from '../audit/audit.module';

@Module({
  imports: [
    AuditModule,
    ConfigModule,
    JwtModule.registerAsync({
      imports:    [ConfigModule],
      inject:     [ConfigService],
      useFactory: (cs: ConfigService) => ({
        secret:      cs.get<string>('JWT_ACCESS_SECRET', 'change_me_access'),
        signOptions: {
          expiresIn: cs.get<string>('JWT_ACCESS_EXPIRES_IN', '15m') as any,
        },
      }),
    }),
  ],
  controllers: [AuthController],
  providers:   [AuthService, FirebaseAuthGuard],
  exports:     [AuthService, FirebaseAuthGuard, JwtModule],
})
export class AuthModule {}
