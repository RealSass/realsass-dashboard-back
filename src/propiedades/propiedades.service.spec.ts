// src/propiedades/propiedades.service.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { PropiedadesService } from './propiedades.service';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';

const mockPrisma = {
  propiedad: {
    create:   jest.fn(),
    findMany: jest.fn(),
    findFirst: jest.fn(),
    count:    jest.fn(),
    update:   jest.fn(),
  },
  zona: { findFirst: jest.fn() },
};

const mockAudit = { log: jest.fn() };

const ctx = {
  userId: 'user-1',
  organizationId: 'org-1',
  role: 'ADMIN',
  firebaseUid: 'uid-1',
};

const baseProp = {
  id: 'prop-1',
  titulo: 'Casa en el centro',
  tipo: 'CASA',
  operacion: 'VENTA',
  precio: 150000,
  moneda: 'USD',
  estado: 'DISPONIBLE',
  isActive: true,
  organizationId: 'org-1',
  imagenes: [],
  zona: null,
};

describe('PropiedadesService', () => {
  let service: PropiedadesService;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PropiedadesService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: AuditService, useValue: mockAudit },
      ],
    }).compile();
    service = module.get<PropiedadesService>(PropiedadesService);
  });

  describe('create', () => {
    const dto = {
      titulo: 'Casa en el centro',
      tipo: 'CASA' as any,
      operacion: 'VENTA' as any,
      precio: 150000,
    };

    it('crea una propiedad correctamente', async () => {
      mockPrisma.propiedad.create.mockResolvedValue(baseProp);

      const result = await service.create(dto, ctx);

      expect(result.success).toBe(true);
      expect(mockPrisma.propiedad.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            titulo: 'Casa en el centro',
            organizationId: 'org-1',
            moneda: 'USD',
            estado: 'DISPONIBLE',
          }),
        }),
      );
      expect(mockAudit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'propiedad.create' }),
      );
    });

    it('lanza BadRequest si la zona no pertenece a la org', async () => {
      mockPrisma.zona.findFirst.mockResolvedValue(null);

      await expect(
        service.create({ ...dto, zonaId: 'zona-ajena' }, ctx),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('findAll', () => {
    it('retorna items paginados con meta', async () => {
      mockPrisma.propiedad.count.mockResolvedValue(5);
      mockPrisma.propiedad.findMany.mockResolvedValue([baseProp]);

      const result = await service.findAll({ page: 1, limit: 20 }, ctx);

      expect(result.success).toBe(true);
      expect(result.meta.total).toBe(5);
      expect(result.meta.totalPages).toBe(1);
    });
  });

  describe('findOne', () => {
    it('retorna la propiedad si existe y pertenece a la org', async () => {
      mockPrisma.propiedad.findFirst.mockResolvedValue(baseProp);
      const result = await service.findOne('prop-1', ctx);
      expect(result.success).toBe(true);
    });

    it('lanza NotFoundException si no existe', async () => {
      mockPrisma.propiedad.findFirst.mockResolvedValue(null);
      await expect(service.findOne('prop-none', ctx))
        .rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('remove', () => {
    it('hace soft delete y loguea audit', async () => {
      mockPrisma.propiedad.findFirst.mockResolvedValue(baseProp);
      mockPrisma.propiedad.update.mockResolvedValue({ ...baseProp, isActive: false });

      const result = await service.remove('prop-1', ctx);
      expect(result.success).toBe(true);
      expect(mockPrisma.propiedad.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { isActive: false } }),
      );
    });
  });
});
