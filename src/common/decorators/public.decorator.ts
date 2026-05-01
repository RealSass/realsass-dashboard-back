// src/common/decorators/public.decorator.ts
import { SetMetadata } from '@nestjs/common';
import { IS_PUBLIC_KEY } from '../../auth/guards/firebase-auth.guard';

export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
