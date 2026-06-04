#!/usr/bin/env bash
# =============================================================================
# fix-dockerfile-nestjs-build.sh
#
# Problema:  Cannot find module '/app/dist/main'
#
# Causas identificadas:
#   1. NODE_ENV=production en el stage builder → pnpm no instala devDependencies
#      → @nestjs/cli no disponible → nest build falla / no emite dist/
#   2. CMD apuntaba a dist/src/main en lugar de dist/main
#      (nest-cli sourceRoot:src + tsconfig outDir:./dist → emite a dist/main.js)
#
# Solución:
#   - Reescribir Dockerfile con NODE_ENV correcto por stage
#   - Stage deps: sin NODE_ENV (instala todo, dev incluido)
#   - Stage builder: NODE_ENV=development para que nest build funcione
#   - Stage runner: NODE_ENV=production
#   - CMD: dumb-init node dist/main  (no dist/src/main)
#
# USO:
#   chmod +x fix-dockerfile-nestjs-build.sh
#   ./fix-dockerfile-nestjs-build.sh
# =============================================================================

set -e
set -o pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
ok()  { echo -e "${GREEN}[OK]${NC}    $1"; }
log() { echo -e "${BLUE}[INFO]${NC}  $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ -f "package.json" ]                    || err "Correr desde la raíz del proyecto"
grep -q '"@nestjs/core"' package.json    || err "No parece ser un proyecto NestJS"

log "Sobreescribiendo Dockerfile..."

cat > Dockerfile << 'DOCKERFILE'
# =============================================================================
# Dockerfile — real-dashboard-back (NestJS)
# node:22-alpine + pnpm@10.11.1
# Multi-stage: deps → builder → runner
#
# IMPORTANTE sobre NODE_ENV:
#   - deps stage:    sin NODE_ENV → instala devDeps (@nestjs/cli, typescript, etc.)
#   - builder stage: NODE_ENV=development → nest build puede usar los devDeps
#   - runner stage:  NODE_ENV=production → solo ejecuta el dist compilado
# =============================================================================

# ── Stage 1: instalar TODAS las dependencias (dev + prod) ────────────────────
FROM node:22-alpine AS deps

RUN corepack enable \
 && corepack prepare pnpm@10.11.1 --activate

WORKDIR /app

COPY package.json .npmrc* ./

# Sin --production: instala devDependencies también (necesarias para compilar)
RUN pnpm install --no-frozen-lockfile

# ── Stage 2: compilar TypeScript con NestJS CLI ───────────────────────────────
FROM node:22-alpine AS builder

RUN corepack enable \
 && corepack prepare pnpm@10.11.1 --activate

WORKDIR /app

# Build args para Prisma (DATABASE_URL puede ser dummy en build-time
# ya que solo se usa en runtime — prisma generate no necesita conectarse)
ARG DATABASE_URL="postgresql://build:build@localhost:5432/build"
ARG FIREBASE_PROJECT_ID
ARG FIREBASE_CLIENT_EMAIL
ARG FIREBASE_PRIVATE_KEY

ENV DATABASE_URL=$DATABASE_URL
ENV FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID
ENV FIREBASE_CLIENT_EMAIL=$FIREBASE_CLIENT_EMAIL
ENV FIREBASE_PRIVATE_KEY=$FIREBASE_PRIVATE_KEY

# NODE_ENV=development para que nest build use devDependencies (@nestjs/cli)
ENV NODE_ENV=development

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# 1. Generar cliente Prisma
# 2. Compilar TypeScript → emite a ./dist/main.js (nest-cli sourceRoot:src + outDir:./dist)
RUN pnpm prisma generate \
 && pnpm run build

# Verificar que el build produjo el artefacto esperado
RUN test -f dist/main.js || (echo "ERROR: dist/main.js no fue generado — revisar errores de nest build" && exit 1)

# ── Stage 3: instalar solo dependencias de producción ────────────────────────
FROM node:22-alpine AS prod-deps

RUN corepack enable \
 && corepack prepare pnpm@10.11.1 --activate

WORKDIR /app

COPY package.json .npmrc* ./

# Solo producción — sin @nestjs/cli ni typescript
RUN pnpm install --no-frozen-lockfile --prod

# ── Stage 4: imagen de producción mínima ─────────────────────────────────────
FROM node:22-alpine AS runner

RUN apk add --no-cache dumb-init

WORKDIR /app

ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 nestjs

# dist/ compilado desde el builder
COPY --from=builder    --chown=nestjs:nodejs /app/dist         ./dist
# node_modules de producción (sin devDeps) → imagen más pequeña
COPY --from=prod-deps  --chown=nestjs:nodejs /app/node_modules ./node_modules
# prisma/ necesario para que el cliente Prisma funcione en runtime
COPY --from=builder    --chown=nestjs:nodejs /app/prisma       ./prisma
COPY --from=builder    --chown=nestjs:nodejs /app/package.json ./package.json

USER nestjs

EXPOSE 3000
ENV PORT=3000

# dist/main.js — ruta correcta para nest-cli con sourceRoot:src + outDir:./dist
CMD ["dumb-init", "node", "dist/main"]
DOCKERFILE

ok "Dockerfile reescrito"

# Actualizar railway.json con el CMD correcto
if [ -f "railway.json" ]; then
  log "Actualizando startCommand en railway.json..."
  # Reemplazar cualquier variante del startCommand
  sed -i 's|"startCommand": ".*dist.*main.*"|"startCommand": "node dist/main"|' railway.json
  ok "railway.json actualizado"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Fix completado${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  CMD correcto: ${GREEN}node dist/main${NC}"
echo -e "  (nest-cli sourceRoot:src + tsconfig outDir:./dist → dist/main.js)"
echo ""
echo -e "${BLUE}Próximos pasos:${NC}"
echo -e "  git add Dockerfile railway.json"
echo -e "  git commit -m 'fix: Dockerfile NODE_ENV stages + correct dist/main path'"
echo -e "  git push"
echo ""