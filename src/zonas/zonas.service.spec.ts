// src/zonas/zonas.service.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { ConflictException, NotFoundException } from '@nestjs/common';
import { ZonasService } from './zonas.service';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';

const mockPrisma = {
  zona: {
    findFirst:  jest.fn(),
    findMany:   jest.fn(),
    create:     jest.fn(),
    update:     jest.fn(),
  },
  propiedad: { count: jest.fn() },
};

const mockAudit = { log: jest.fn() };

const ctx = {
  userId: 'user-1',
  organizationId: 'org-1',
  role: 'ADMIN',
  firebaseUid: 'uid-1',
};

describe('ZonasService', () => {
  let service: ZonasService;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ZonasService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: AuditService, useValue: mockAudit },
      ],
    }).compile();
    service = module.get<ZonasService>(ZonasService);
  });

  describe('create', () => {
    it('crea una zona y loguea el audit', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue(null);
      mockPrisma.zona.create.mockResolvedValue({ id: 'zona-1', nombre: 'Centro' });

      const result = await service.create({ nombre: 'Centro' }, ctx);

      expect(result.success).toBe(true);
      expect(mockPrisma.zona.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            nombre: 'Centro',
            organizationId: 'org-1',
          }),
        }),
      );
      expect(mockAudit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'zona.create' }),
      );
    });

    it('lanza ConflictException si el nombre ya existe en la org', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue({ id: 'zona-1', nombre: 'Centro' });

      await expect(service.create({ nombre: 'Centro' }, ctx))
        .rejects.toBeInstanceOf(ConflictException);
    });
  });

  describe('remove', () => {
    it('lanza ConflictException si tiene propiedades activas', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue({ id: 'zona-1', nombre: 'Centro' });
      mockPrisma.propiedad.count.mockResolvedValue(3);

      await expect(service.remove('zona-1', ctx))
        .rejects.toBeInstanceOf(ConflictException);
    });

    it('desactiva la zona si no tiene propiedades activas', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue({ id: 'zona-1', nombre: 'Centro' });
      mockPrisma.propiedad.count.mockResolvedValue(0);
      mockPrisma.zona.update.mockResolvedValue({ id: 'zona-1', isActive: false });

      const result = await service.remove('zona-1', ctx);
      expect(result.success).toBe(true);
    });
  });
});
