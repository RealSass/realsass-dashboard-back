// src/propiedades/dto/update-propiedad.dto.ts
import { PartialType } from '@nestjs/mapped-types';
import { CreatePropiedadDto } from './create-propiedad.dto';

export class UpdatePropiedadDto extends PartialType(CreatePropiedadDto) {}
