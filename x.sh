#!/usr/bin/env bash
# =============================================================================
# fix-railway-real-back.sh
#
# Problema:  pnpm-workspace.yaml existe sin campo "packages" → Railway activa
#            el path de monorepo y falla con "packages field missing or empty".
#
# Solución:
#   1. Elimina pnpm-workspace.yaml y mueve allowBuilds a .npmrc
#   2. Crea Dockerfile multi-stage para NestJS (build + runner)
#   3. Crea railway.json forzando builder Dockerfile
#   4. Crea .dockerignore
#   5. Fija packageManager en package.json
#   6. Regenera pnpm-lock.yaml
#
# IMPORTANTE: Este es un backend NestJS — el runner usa "node dist/main",
#             NO "node server.js" como los frontends Next.js.
#
# USO:
#   chmod +x fix-railway-real-back.sh
#   ./fix-railway-real-back.sh
# =============================================================================

set -e
set -o pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ -f "package.json" ]              || err "Correr desde la raíz del proyecto real-back"
command -v pnpm &>/dev/null        || err "pnpm no encontrado. Instalar: npm i -g pnpm"
grep -q '"@nestjs/core"' package.json || err "No parece ser un proyecto NestJS"

# ─── 1. Eliminar pnpm-workspace.yaml ─────────────────────────────────────────
log "Paso 1 — Eliminando pnpm-workspace.yaml..."

if [ -f "pnpm-workspace.yaml" ]; then
  rm pnpm-workspace.yaml
  ok "pnpm-workspace.yaml eliminado"
else
  warn "pnpm-workspace.yaml no encontrado — ya fue eliminado"
fi

# ─── 2. Escribir .npmrc ───────────────────────────────────────────────────────
log "Paso 2 — Escribiendo .npmrc con allowBuilds..."

cat > .npmrc << 'NPMRC'
# Permite scripts de build para paquetes nativos de Firebase / Prisma
allow-build[]=@firebase/util
allow-build[]=@nestjs/core
allow-build[]=@prisma/engines
allow-build[]=prisma
allow-build[]=protobufjs
allow-build[]=unrs-resolver
fund=false
update-notifier=false
NPMRC

ok ".npmrc escrito"

# ─── 3. Fijar packageManager en package.json ─────────────────────────────────
log "Paso 3 — Fijando packageManager: pnpm@10.11.1 en package.json..."

if grep -q '"packageManager"' package.json; then
  sed -i 's/"packageManager": "pnpm@[^"]*"/"packageManager": "pnpm@10.11.1"/' package.json
  ok "packageManager actualizado a pnpm@10.11.1"
else
  sed -i 's/"private": true,/"private": true,\n  "packageManager": "pnpm@10.11.1",/' package.json
  ok "packageManager: pnpm@10.11.1 agregado"
fi

# ─── 4. Crear Dockerfile multi-stage NestJS ───────────────────────────────────
log "Paso 4 — Creando Dockerfile para NestJS..."

cat > Dockerfile << 'DOCKERFILE'
# =============================================================================
# Dockerfile — real-back (NestJS)
# node:22-alpine + pnpm@10.11.1
# Multi-stage: deps → builder → runner
#
# El runner copia solo dist/ y node_modules de producción → imagen mínima.
# Prisma genera el cliente en el stage builder y se copia al runner.
# =============================================================================

# ── Stage 1: dependencias de producción ──────────────────────────────────────
FROM node:22-alpine AS deps

RUN corepack enable \
 && corepack prepare pnpm@10.11.1 --activate

WORKDIR /app

COPY package.json .npmrc* ./

# Instalar TODAS las dependencias (dev incluidas, necesarias para el build)
RUN pnpm install --no-frozen-lockfile

# ── Stage 2: compilar TypeScript ──────────────────────────────────────────────
FROM node:22-alpine AS builder

RUN corepack enable \
 && corepack prepare pnpm@10.11.1 --activate

WORKDIR /app

# Variables de entorno necesarias en build-time
# (Prisma necesita DATABASE_URL para generate si usa datasource env())
ARG DATABASE_URL
ARG FIREBASE_PROJECT_ID
ARG FIREBASE_CLIENT_EMAIL
ARG FIREBASE_PRIVATE_KEY

ENV DATABASE_URL=$DATABASE_URL
ENV FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID
ENV FIREBASE_CLIENT_EMAIL=$FIREBASE_CLIENT_EMAIL
ENV FIREBASE_PRIVATE_KEY=$FIREBASE_PRIVATE_KEY
ENV NODE_ENV=production

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Generar cliente Prisma + compilar TypeScript
RUN pnpm prisma generate \
 && pnpm run build

# ── Stage 3: imagen de producción mínima ─────────────────────────────────────
FROM node:22-alpine AS runner

RUN apk add --no-cache dumb-init

WORKDIR /app

ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 nestjs

# Copiar solo lo necesario para runtime
COPY --from=builder --chown=nestjs:nodejs /app/dist           ./dist
COPY --from=builder --chown=nestjs:nodejs /app/node_modules   ./node_modules
COPY --from=builder --chown=nestjs:nodejs /app/prisma         ./prisma
COPY --from=builder --chown=nestjs:nodejs /app/package.json   ./package.json

USER nestjs

EXPOSE 3000
ENV PORT=3000

# dumb-init maneja señales correctamente (graceful shutdown)
CMD ["dumb-init", "node", "dist/main"]
DOCKERFILE

ok "Dockerfile creado"

# ─── 5. railway.json ──────────────────────────────────────────────────────────
log "Paso 5 — Creando railway.json..."

cat > railway.json << 'RAILWAYJSON'
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "DOCKERFILE",
    "dockerfilePath": "Dockerfile"
  },
  "deploy": {
    "startCommand": "node dist/main",
    "healthcheckPath": "/health",
    "healthcheckTimeout": 300,
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 3
  }
}
RAILWAYJSON

ok "railway.json creado"

# ─── 6. .dockerignore ─────────────────────────────────────────────────────────
log "Paso 6 — Creando .dockerignore..."

cat > .dockerignore << 'DOCKERIGNORE'
# Build output — se regenera en el stage builder
dist
build

# Dependencies — se reinstalan en el stage deps
node_modules
.pnpm-store

# Entornos locales — NUNCA al contenedor
.env
.env.local
.env.*.local

# Dev/test
__tests__
test
*.test.ts
*.spec.ts
coverage
jest.config.*

# Git y CI
.git
.gitignore
.github

# Docker mismo
Dockerfile*
.dockerignore
railway.json

# Logs
*.log
logs/

# OS
.DS_Store
Thumbs.db

# Docs
*.md
README*
CHANGELOG*
DOCKERIGNORE

ok ".dockerignore creado"

# ─── 7. Regenerar pnpm-lock.yaml ─────────────────────────────────────────────
log "Paso 7 — Regenerando pnpm-lock.yaml con pnpm@10.11.1..."

corepack prepare pnpm@10.11.1 --activate 2>/dev/null || {
  warn "corepack prepare falló — instalando pnpm@10.11.1 via npm"
  npm install -g pnpm@10.11.1
}

pnpm install --no-frozen-lockfile
ok "pnpm-lock.yaml regenerado"

# ─── Resumen ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Fix completado — real-back (NestJS)${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}ELIMINADO${NC}   pnpm-workspace.yaml"
echo -e "  ${GREEN}CREADO${NC}      .npmrc"
echo -e "  ${GREEN}MODIFICADO${NC}  package.json      (+ packageManager: pnpm@10.11.1)"
echo -e "  ${GREEN}CREADO${NC}      Dockerfile        (node:22-alpine, NestJS multi-stage)"
echo -e "  ${GREEN}CREADO${NC}      railway.json"
echo -e "  ${GREEN}CREADO${NC}      .dockerignore"
echo -e "  ${GREEN}REGENERADO${NC}  pnpm-lock.yaml"
echo ""
echo -e "${BLUE}Próximos pasos:${NC}"
echo -e "  1. git add -A"
echo -e "  2. git commit -m 'fix: railway deploy real-back — Dockerfile NestJS + pnpm@10.11.1'"
echo -e "  3. git push"
echo ""
echo -e "${BLUE}Variables de entorno en Railway → real-back → Variables:${NC}"
echo -e "  DATABASE_URL          = <connection string de real_back_db>"
echo -e "  FIREBASE_PROJECT_ID   = <tu firebase project id>"
echo -e "  FIREBASE_CLIENT_EMAIL = <service account email>"
echo -e "  FIREBASE_PRIVATE_KEY  = <private key con \\\\n literales>"
echo -e "  NODE_ENV              = production"
echo -e "  PORT                  = 3000"
echo -e "  ALLOWED_ORIGINS       = <URL del real-front en Railway>"
echo ""
echo -e "${YELLOW}Nota Prisma:${NC} El Dockerfile corre 'prisma generate' en build-time."
echo -e "  Las migraciones ('prisma migrate deploy') deben correrse por separado"
echo -e "  usando el script setup-railway-databases.sh o desde Railway CLI."
echo ""