-- CreateEnum
CREATE TYPE "Role" AS ENUM ('ADMIN', 'VENDEDOR', 'VIEWER');

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "nombre" TEXT NOT NULL,
    "firebase_uid" TEXT,
    "firebase_email" TEXT,
    "password_hash" TEXT,
    "refresh_token" TEXT,
    "role" "Role" NOT NULL DEFAULT 'VENDEDOR',
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organizations" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "enabled_products" JSONB NOT NULL DEFAULT '{}',
    "system_settings" JSONB NOT NULL DEFAULT '{}',
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "organizations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "puntos_de_venta" (
    "id" TEXT NOT NULL,
    "nombre" TEXT NOT NULL,
    "direccion" TEXT,
    "ciudad" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "organization_id" TEXT NOT NULL,

    CONSTRAINT "puntos_de_venta_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "accesorios" (
    "id" TEXT NOT NULL,
    "nombre" TEXT NOT NULL,
    "modelo" TEXT NOT NULL,
    "tipo" TEXT NOT NULL,
    "descripcion" TEXT,
    "cantidad" INTEGER NOT NULL DEFAULT 0,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "organization_id" TEXT NOT NULL,
    "punto_de_venta_id" TEXT NOT NULL,

    CONSTRAINT "accesorios_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "accesorio_colores" (
    "id" TEXT NOT NULL,
    "color" TEXT NOT NULL,
    "accesorio_id" TEXT NOT NULL,

    CONSTRAINT "accesorio_colores_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "accesorio_imagenes" (
    "id" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "orden" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "accesorio_id" TEXT NOT NULL,

    CONSTRAINT "accesorio_imagenes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sub_accesorios" (
    "id" TEXT NOT NULL,
    "nombre" TEXT NOT NULL,
    "tipo" TEXT NOT NULL,
    "descripcion" TEXT,
    "cantidad" INTEGER NOT NULL DEFAULT 0,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "organization_id" TEXT NOT NULL,
    "punto_de_venta_id" TEXT NOT NULL,

    CONSTRAINT "sub_accesorios_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sub_accesorio_colores" (
    "id" TEXT NOT NULL,
    "color" TEXT NOT NULL,
    "sub_accesorio_id" TEXT NOT NULL,

    CONSTRAINT "sub_accesorio_colores_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sub_accesorio_imagenes" (
    "id" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "orden" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sub_accesorio_id" TEXT NOT NULL,

    CONSTRAINT "sub_accesorio_imagenes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "entity_type" TEXT NOT NULL,
    "entity_id" TEXT,
    "payload" JSONB NOT NULL DEFAULT '{}',
    "ip_address" TEXT,
    "user_agent" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "user_id" TEXT,
    "organization_id" TEXT,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "users_firebase_uid_key" ON "users"("firebase_uid");

-- CreateIndex
CREATE INDEX "users_email_idx" ON "users"("email");

-- CreateIndex
CREATE INDEX "users_firebase_uid_idx" ON "users"("firebase_uid");

-- CreateIndex
CREATE UNIQUE INDEX "organizations_slug_key" ON "organizations"("slug");

-- CreateIndex
CREATE INDEX "organizations_slug_idx" ON "organizations"("slug");

-- CreateIndex
CREATE INDEX "puntos_de_venta_organization_id_idx" ON "puntos_de_venta"("organization_id");

-- CreateIndex
CREATE INDEX "accesorios_organization_id_idx" ON "accesorios"("organization_id");

-- CreateIndex
CREATE INDEX "accesorios_punto_de_venta_id_idx" ON "accesorios"("punto_de_venta_id");

-- CreateIndex
CREATE INDEX "accesorios_nombre_idx" ON "accesorios"("nombre");

-- CreateIndex
CREATE INDEX "accesorios_tipo_idx" ON "accesorios"("tipo");

-- CreateIndex
CREATE INDEX "accesorio_colores_accesorio_id_idx" ON "accesorio_colores"("accesorio_id");

-- CreateIndex
CREATE INDEX "accesorio_imagenes_accesorio_id_idx" ON "accesorio_imagenes"("accesorio_id");

-- CreateIndex
CREATE INDEX "sub_accesorios_organization_id_idx" ON "sub_accesorios"("organization_id");

-- CreateIndex
CREATE INDEX "sub_accesorios_punto_de_venta_id_idx" ON "sub_accesorios"("punto_de_venta_id");

-- CreateIndex
CREATE INDEX "sub_accesorios_nombre_idx" ON "sub_accesorios"("nombre");

-- CreateIndex
CREATE INDEX "sub_accesorios_tipo_idx" ON "sub_accesorios"("tipo");

-- CreateIndex
CREATE INDEX "sub_accesorio_colores_sub_accesorio_id_idx" ON "sub_accesorio_colores"("sub_accesorio_id");

-- CreateIndex
CREATE INDEX "sub_accesorio_imagenes_sub_accesorio_id_idx" ON "sub_accesorio_imagenes"("sub_accesorio_id");

-- CreateIndex
CREATE INDEX "audit_logs_organization_id_idx" ON "audit_logs"("organization_id");

-- CreateIndex
CREATE INDEX "audit_logs_user_id_idx" ON "audit_logs"("user_id");

-- CreateIndex
CREATE INDEX "audit_logs_entity_type_entity_id_idx" ON "audit_logs"("entity_type", "entity_id");

-- CreateIndex
CREATE INDEX "audit_logs_created_at_idx" ON "audit_logs"("created_at");

-- AddForeignKey
ALTER TABLE "puntos_de_venta" ADD CONSTRAINT "puntos_de_venta_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "accesorios" ADD CONSTRAINT "accesorios_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "accesorios" ADD CONSTRAINT "accesorios_punto_de_venta_id_fkey" FOREIGN KEY ("punto_de_venta_id") REFERENCES "puntos_de_venta"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "accesorio_colores" ADD CONSTRAINT "accesorio_colores_accesorio_id_fkey" FOREIGN KEY ("accesorio_id") REFERENCES "accesorios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "accesorio_imagenes" ADD CONSTRAINT "accesorio_imagenes_accesorio_id_fkey" FOREIGN KEY ("accesorio_id") REFERENCES "accesorios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sub_accesorios" ADD CONSTRAINT "sub_accesorios_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sub_accesorios" ADD CONSTRAINT "sub_accesorios_punto_de_venta_id_fkey" FOREIGN KEY ("punto_de_venta_id") REFERENCES "puntos_de_venta"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sub_accesorio_colores" ADD CONSTRAINT "sub_accesorio_colores_sub_accesorio_id_fkey" FOREIGN KEY ("sub_accesorio_id") REFERENCES "sub_accesorios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sub_accesorio_imagenes" ADD CONSTRAINT "sub_accesorio_imagenes_sub_accesorio_id_fkey" FOREIGN KEY ("sub_accesorio_id") REFERENCES "sub_accesorios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE SET NULL ON UPDATE CASCADE;
