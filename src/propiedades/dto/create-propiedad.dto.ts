// src/propiedades/dto/create-propiedad.dto.ts
import {
  IsArray,
  IsEnum,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ArrayMaxSize,
  IsBoolean,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export enum TipoPropiedad {
  CASA        = 'CASA',
  DEPARTAMENTO = 'DEPARTAMENTO',
  TERRENO     = 'TERRENO',
  LOCAL       = 'LOCAL',
  OFICINA     = 'OFICINA',
  GALPON      = 'GALPON',
  CAMPO       = 'CAMPO',
}

export enum TipoOperacion {
  VENTA        = 'VENTA',
  ALQUILER     = 'ALQUILER',
  ALQUILER_TEMP = 'ALQUILER_TEMP',
}

export enum EstadoPropiedad {
  DISPONIBLE = 'DISPONIBLE',
  RESERVADA  = 'RESERVADA',
  VENDIDA    = 'VENDIDA',
  ALQUILADA  = 'ALQUILADA',
  PAUSADA    = 'PAUSADA',
}

export class CreatePropiedadDto {
  @ApiProperty({ example: 'Hermosa casa en el centro' })
  @IsString()
  @MaxLength(200)
  titulo: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  descripcion?: string;

  @ApiProperty({ enum: TipoPropiedad })
  @IsEnum(TipoPropiedad)
  tipo: TipoPropiedad;

  @ApiProperty({ enum: TipoOperacion })
  @IsEnum(TipoOperacion)
  operacion: TipoOperacion;

  @ApiProperty({ example: 150000 })
  @IsNumber()
  @Min(0)
  precio: number;

  @ApiPropertyOptional({ example: 'USD', default: 'USD' })
  @IsOptional()
  @IsString()
  moneda?: string;

  @ApiPropertyOptional({ example: 120.5 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  superficie?: number;

  @ApiPropertyOptional({ example: 4 })
  @IsOptional()
  @IsInt()
  @Min(0)
  ambientes?: number;

  @ApiPropertyOptional({ example: 2 })
  @IsOptional()
  @IsInt()
  @Min(0)
  banos?: number;

  @ApiPropertyOptional({ example: 3 })
  @IsOptional()
  @IsInt()
  @Min(0)
  dormitorios?: number;

  @ApiPropertyOptional({ example: 'Av. Güemes 245' })
  @IsOptional()
  @IsString()
  @MaxLength(300)
  direccion?: string;

  @ApiPropertyOptional({ enum: EstadoPropiedad, default: 'DISPONIBLE' })
  @IsOptional()
  @IsEnum(EstadoPropiedad)
  estado?: EstadoPropiedad;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  destacada?: boolean;

  @ApiPropertyOptional({ description: 'ID de la zona' })
  @IsOptional()
  @IsString()
  zonaId?: string;

  @ApiPropertyOptional({ description: 'URLs de imágenes (máx 10)', type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @ArrayMaxSize(10, { message: 'No se pueden cargar más de 10 imágenes' })
  imagenes?: string[];
}
