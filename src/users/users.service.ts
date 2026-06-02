// src/users/users.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findById(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: {
        id:          true,
        email:       true,
        nombre:      true,
        role:        true,
        firebaseUid: true,
        isActive:    true,
        createdAt:   true,
      },
    });

    if (!user) throw new NotFoundException('Usuario no encontrado');
    return user;
  }

  async findByFirebaseUid(firebaseUid: string) {
    const user = await this.prisma.user.findUnique({
      where: { firebaseUid },
      select: {
        id:          true,
        email:       true,
        nombre:      true,
        role:        true,
        firebaseUid: true,
        isActive:    true,
        createdAt:   true,
      },
    });

    if (!user) throw new NotFoundException('Usuario no encontrado');
    return user;
  }
}
