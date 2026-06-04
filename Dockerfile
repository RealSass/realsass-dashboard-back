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
RUN test -f dist/src/main.js || (echo "ERROR: dist/src/main.js no fue generado" && exit 1)

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

# Copiar node_modules del BUILDER (tiene @prisma/client generado)
# NO usar prod-deps — prisma generate crea .prisma/client que prod-deps no tiene
COPY --from=builder    --chown=nestjs:nodejs /app/dist         ./dist
COPY --from=builder    --chown=nestjs:nodejs /app/node_modules ./node_modules
COPY --from=builder    --chown=nestjs:nodejs /app/prisma       ./prisma
COPY --from=builder    --chown=nestjs:nodejs /app/package.json ./package.json

USER nestjs

EXPOSE 3000
ENV PORT=3000

CMD ["dumb-init", "node", "dist/src/main"]
