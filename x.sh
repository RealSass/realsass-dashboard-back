#!/usr/bin/env bash
# =============================================================================
#  fix-seed-relations.sh
#  Corrige prisma/seed.ts: Accesorio y SubAccesorio requieren connect en
#  AMBAS relaciones: organization + puntoDeVenta
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${BLUE}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✔ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

log "Reescribiendo prisma/seed.ts con ambas relaciones (organization + puntoDeVenta)..."

cat > prisma/seed.ts << 'EOF'
// prisma/seed.ts
import { PrismaClient, Role } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';
import * as pg from 'pg';
import * as dotenv from 'dotenv';
import * as bcrypt from 'bcrypt';

dotenv.config();

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

const SEED_ORG_ID = '00000000-0000-0000-0000-000000000000';
const SEED_PDV_ID = '00000000-0000-0000-0000-000000000001';

async function main() {
  console.log('🌱 Iniciando seed...');

  // ─── Organización base ────────────────────────────────────────────────────
  const org = await prisma.organization.upsert({
    where:  { id: SEED_ORG_ID },
    update: {},
    create: {
      id:              SEED_ORG_ID,
      name:            'Todo Apple',
      slug:            'todo-apple',
      enabledProducts: {},
      systemSettings:  {},
    },
  });
  console.log('✅ Organización:', org.name);

  // ─── Usuarios Admin ───────────────────────────────────────────────────────
  const users = [
    { email: 'marcos@todoapple.com', nombre: 'Marcos' },
    { email: 'store@todoapple.com',  nombre: 'Store'  },
  ];

  for (const u of users) {
    const passwordHash = await bcrypt.hash(u.email, 10);
    const user = await prisma.user.upsert({
      where:  { email: u.email },
      update: {},
      create: {
        email:        u.email,
        nombre:       u.nombre,
        passwordHash,
        role:         Role.ADMIN,
      },
    });
    console.log(`✅ Usuario admin: ${user.email}`);
  }

  // ─── Punto de Venta ───────────────────────────────────────────────────────
  const pdv = await prisma.puntoDeVenta.upsert({
    where:  { id: SEED_PDV_ID },
    update: {},
    create: {
      id:           SEED_PDV_ID,
      nombre:       'Local Centro',
      direccion:    'Bonifacio Córdoba 678',
      ciudad:       'San Fernando del Valle de Catamarca',
      organization: { connect: { id: SEED_ORG_ID } },
    },
  });
  console.log('✅ PdV:', pdv.nombre);

  // ─── Accesorios de marca ──────────────────────────────────────────────────
  console.log('\n🎒 Cargando accesorios de marca...');

  const accesoriosData = [
    {
      nombre:      'iPhone 15',
      modelo:      'Pro',
      tipo:        'Funda',
      descripcion: 'Funda de silicona con MagSafe',
      cantidad:    16,
      colores:     ['Rosa', 'Negro', 'Azul'],
      imagenes: [
        'https://store.storeimages.cdn-apple.com/funda-magsafe-rosa.jpg',
        'https://store.storeimages.cdn-apple.com/funda-magsafe-negro.jpg',
      ],
    },
    {
      nombre:      'iPhone 15',
      modelo:      'Standard',
      tipo:        'Templado',
      descripcion: 'Vidrio templado 9H',
      cantidad:    20,
      colores:     [],
      imagenes:    ['https://store.storeimages.cdn-apple.com/templado-iphone15.jpg'],
    },
    {
      nombre:      'iPhone 14',
      modelo:      'Standard',
      tipo:        'Funda',
      descripcion: 'Funda transparente antigolpes',
      cantidad:    10,
      colores:     ['Transparente', 'Negro'],
      imagenes:    ['https://store.storeimages.cdn-apple.com/funda-iphone14-transparente.jpg'],
    },
    {
      nombre:      'AirPods Pro',
      modelo:      '2da Gen',
      tipo:        'Funda',
      descripcion: 'Funda de silicona para AirPods Pro',
      cantidad:    8,
      colores:     ['Blanco', 'Negro'],
      imagenes:    ['https://store.storeimages.cdn-apple.com/funda-airpods-pro.jpg'],
    },
    {
      nombre:      'Apple Watch',
      modelo:      'Series 9',
      tipo:        'Malla',
      descripcion: 'Malla deportiva original',
      cantidad:    6,
      colores:     ['Medianoche', 'Starlight', 'Rojo'],
      imagenes: [
        'https://store.storeimages.cdn-apple.com/malla-watch-s9.jpg',
        'https://store.storeimages.cdn-apple.com/malla-watch-s9-colores.jpg',
      ],
    },
  ];

  for (const a of accesoriosData) {
    const accesorio = await prisma.accesorio.create({
      data: {
        nombre:       a.nombre,
        modelo:       a.modelo,
        tipo:         a.tipo,
        descripcion:  a.descripcion,
        cantidad:     a.cantidad,
        // Ambas relaciones requeridas deben ir con connect
        organization: { connect: { id: SEED_ORG_ID } },
        puntoDeVenta: { connect: { id: SEED_PDV_ID } },
        colores:  { create: a.colores.map((color) => ({ color })) },
        imagenes: { create: a.imagenes.map((url, i) => ({ url, orden: i })) },
      },
    });
    console.log(`  ✅ ${accesorio.nombre} ${accesorio.modelo} — ${a.tipo}`);
  }

  // ─── Sub Accesorios (genéricos sin marca) ─────────────────────────────────
  console.log('\n📦 Cargando sub accesorios genéricos...');

  const subAccesoriosData = [
    {
      nombre:      'Cable USB-C',
      tipo:        'Cable',
      descripcion: 'Cable trenzado USB-C a USB-C 2 metros',
      cantidad:    25,
      colores:     ['Blanco', 'Negro'],
      imagenes: [
        'https://images.example.com/cable-usbc-blanco.jpg',
        'https://images.example.com/cable-usbc-negro.jpg',
      ],
    },
    {
      nombre:      'Cargador 20W',
      tipo:        'Cargador',
      descripcion: 'Cargador rápido USB-C 20W',
      cantidad:    15,
      colores:     ['Blanco'],
      imagenes:    ['https://images.example.com/cargador-20w.jpg'],
    },
    {
      nombre:      'Auriculares In-Ear',
      tipo:        'Auriculares',
      descripcion: 'Auriculares con cable USB-C, compatibles con todos los dispositivos',
      cantidad:    12,
      colores:     ['Blanco', 'Negro', 'Rojo'],
      imagenes: [
        'https://images.example.com/auriculares-inear.jpg',
        'https://images.example.com/auriculares-inear-colores.jpg',
      ],
    },
    {
      nombre:      'Soporte de Auto',
      tipo:        'Soporte',
      descripcion: 'Soporte magnético para auto, compatible con MagSafe',
      cantidad:    9,
      colores:     ['Negro'],
      imagenes:    ['https://images.example.com/soporte-auto.jpg'],
    },
    {
      nombre:      'Power Bank 10000mAh',
      tipo:        'Batería',
      descripcion: 'Batería portátil 10000mAh con carga rápida USB-C',
      cantidad:    7,
      colores:     ['Negro', 'Blanco'],
      imagenes: [
        'https://images.example.com/powerbank-negro.jpg',
        'https://images.example.com/powerbank-blanco.jpg',
      ],
    },
  ];

  for (const s of subAccesoriosData) {
    const sub = await prisma.subAccesorio.create({
      data: {
        nombre:       s.nombre,
        tipo:         s.tipo,
        descripcion:  s.descripcion,
        cantidad:     s.cantidad,
        // Ambas relaciones requeridas deben ir con connect
        organization: { connect: { id: SEED_ORG_ID } },
        puntoDeVenta: { connect: { id: SEED_PDV_ID } },
        colores:  { create: s.colores.map((color) => ({ color })) },
        imagenes: { create: s.imagenes.map((url, i) => ({ url, orden: i })) },
      },
    });
    console.log(`  ✅ ${sub.nombre} — ${sub.tipo} — stock: ${s.cantidad}`);
  }

  console.log('\n🎉 Seed completado');
  console.log('─────────────────────────────────────────────────────');
  console.log(`👤 Admins:         marcos@todoapple.com / store@todoapple.com`);
  console.log(`🏢 Organización:   Todo Apple (${SEED_ORG_ID})`);
  console.log(`🏪 PdV:            Local Centro — Catamarca`);
  console.log(`🎒 Accesorios:     ${accesoriosData.length}`);
  console.log(`📦 SubAccesorios:  ${subAccesoriosData.length}`);
}

main()
  .catch((e) => { console.error('❌', e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); await pool.end(); });
EOF
ok "prisma/seed.ts corregido (ambas relaciones con connect)"

# ---------------------------------------------------------------------------
# Verificar build
# ---------------------------------------------------------------------------
log "Ejecutando pnpm run build..."
pnpm run build && ok "✅ Build exitoso — 0 errores" || {
  warn "Build falló. Revisá los errores arriba."
  exit 1
}

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Completado${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"