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
CMD ["dumb-init", "node", "dist/src/main"]
