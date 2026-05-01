// src/accesorios/dto/create-accesorio.dto.ts
import {
  ArrayMaxSize,
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';

export class CreateAccesorioDto {
  @IsString()
  nombre: string;

  @IsString()
  modelo: string;

  @IsString()
  tipo: string;

  @IsOptional()
  @IsString()
  descripcion?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  cantidad?: number;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  colores?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @ArrayMaxSize(5, { message: 'No se pueden cargar más de 5 imágenes' })
  imagenes?: string[];

  @IsString()
  puntoDeVentaId: string;
}
