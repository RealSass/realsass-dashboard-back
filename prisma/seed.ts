// prisma/seed.ts
import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';
import * as pg from 'pg';

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter } as any);

const SEED_ORG_ID = 'org-real-estate-seed-000000000001';

async function main() {
  console.log('🌱 Iniciando seed — Real Estate Dashboard\n');

  // ── Organización demo ──────────────────────────────────────────────────────
  const org = await prisma.organization.upsert({
    where: { id: SEED_ORG_ID },
    update: {},
    create: {
      id:   SEED_ORG_ID,
      name: 'Inmobiliaria San Martín',
      slug: 'inmobiliaria-san-martin',
      enabledProducts: {
        propiedades: true,
        chat:        true,
        pagos:       false,
        campanas:    false,
      },
      systemSettings: {},
    },
  });
  console.log(`✅ Organización: ${org.name} (${org.id})`);

  // ── Zonas ─────────────────────────────────────────────────────────────────
  console.log('\n📍 Creando zonas...');

  const zonasData = [
    { nombre: 'Centro',         ciudad: 'San Fernando del Valle', provincia: 'Catamarca' },
    { nombre: 'Norte',          ciudad: 'San Fernando del Valle', provincia: 'Catamarca' },
    { nombre: 'Zona Residencial', ciudad: 'San Fernando del Valle', provincia: 'Catamarca' },
  ];

  const zonas: Record<string, string> = {};
  for (const z of zonasData) {
    const zona = await prisma.zona.upsert({
      where: { id: `zona-${z.nombre.toLowerCase().replace(/ /g, '-')}-seed` },
      update: {},
      create: {
        id:             `zona-${z.nombre.toLowerCase().replace(/ /g, '-')}-seed`,
        nombre:         z.nombre,
        ciudad:         z.ciudad,
        provincia:      z.provincia,
        organizationId: SEED_ORG_ID,
      },
    });
    zonas[z.nombre] = zona.id;
    console.log(`  ✅ ${zona.nombre}`);
  }

  // ── Propiedades demo ───────────────────────────────────────────────────────
  console.log('\n🏠 Creando propiedades demo...');

  const propiedadesData = [
    {
      titulo: 'Casa amplia en el centro con jardín',
      tipo: 'CASA', operacion: 'VENTA', precio: 180000, moneda: 'USD',
      superficie: 180, ambientes: 5, banos: 2, dormitorios: 3,
      direccion: 'Av. Güemes 245, Centro',
      estado: 'DISPONIBLE', destacada: true, zona: 'Centro',
    },
    {
      titulo: 'Departamento moderno 2 ambientes',
      tipo: 'DEPARTAMENTO', operacion: 'ALQUILER', precio: 120000, moneda: 'ARS',
      superficie: 55, ambientes: 2, banos: 1, dormitorios: 1,
      direccion: 'Sarmiento 780, Centro',
      estado: 'DISPONIBLE', destacada: false, zona: 'Centro',
    },
    {
      titulo: 'Terreno con vista al cerro',
      tipo: 'TERRENO', operacion: 'VENTA', precio: 45000, moneda: 'USD',
      superficie: 600, ambientes: null, banos: null, dormitorios: null,
      direccion: 'Camino al Portezuelo s/n',
      estado: 'DISPONIBLE', destacada: false, zona: 'Norte',
    },
    {
      titulo: 'Casa en barrio residencial — 4 dormitorios',
      tipo: 'CASA', operacion: 'VENTA', precio: 250000, moneda: 'USD',
      superficie: 220, ambientes: 6, banos: 3, dormitorios: 4,
      direccion: 'Los Aromos 123',
      estado: 'RESERVADA', destacada: true, zona: 'Zona Residencial',
    },
  ];

  for (const p of propiedadesData) {
    const propiedad = await prisma.propiedad.create({
      data: {
        titulo:         p.titulo,
        tipo:           p.tipo as any,
        operacion:      p.operacion as any,
        precio:         p.precio,
        moneda:         p.moneda,
        superficie:     p.superficie,
        ambientes:      p.ambientes,
        banos:          p.banos,
        dormitorios:    p.dormitorios,
        direccion:      p.direccion,
        estado:         p.estado as any,
        destacada:      p.destacada,
        organizationId: SEED_ORG_ID,
        zonaId:         zonas[p.zona],
      },
    });
    console.log(`  ✅ ${propiedad.titulo.slice(0, 50)}...`);
  }

  console.log('\n🎉 Seed completado');
  console.log('─────────────────────────────────────────────────────');
  console.log(`🏢 Organización: ${org.name}`);
  console.log(`📍 Zonas:        ${zonasData.length}`);
  console.log(`🏠 Propiedades:  ${propiedadesData.length}`);
}

main()
  .catch((e) => { console.error('❌', e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); await pool.end(); });
