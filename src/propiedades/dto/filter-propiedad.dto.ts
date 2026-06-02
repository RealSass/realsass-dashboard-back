// src/propiedades/dto/filter-propiedad.dto.ts
import { IsEnum, IsInt, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { TipoPropiedad, TipoOperacion, EstadoPropiedad } from './create-propiedad.dto';

export class FilterPropiedadDto {
  @ApiPropertyOptional({ enum: TipoPropiedad })
  @IsOptional()
  @IsEnum(TipoPropiedad)
  tipo?: TipoPropiedad;

  @ApiPropertyOptional({ enum: TipoOperacion })
  @IsOptional()
  @IsEnum(TipoOperacion)
  operacion?: TipoOperacion;

  @ApiPropertyOptional({ enum: EstadoPropiedad })
  @IsOptional()
  @IsEnum(EstadoPropiedad)
  estado?: EstadoPropiedad;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  zonaId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  precioMin?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  precioMax?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  buscar?: string;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional()
  @IsInt()
  @Min(1)
  limit?: number = 20;
}
