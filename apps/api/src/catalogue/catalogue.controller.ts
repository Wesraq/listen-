import { Controller, Get, Inject, Param, Query } from '@nestjs/common';

import { CatalogueService } from './catalogue.service';
import { ContentFormat } from './catalogue.types';

@Controller('catalogue')
export class CatalogueController {
  constructor(@Inject(CatalogueService) private readonly catalogue: CatalogueService) {}

  @Get('titles')
  listTitles(
    @Query('format') format?: ContentFormat,
    @Query('category') category?: string,
  ) {
    return {
      items: this.catalogue.listTitles(format, category),
    };
  }

  @Get('titles/:id')
  getTitle(@Param('id') id: string) {
    return this.catalogue.getTitle(id);
  }

  @Get('titles/:id/chapters')
  getChapters(@Param('id') id: string) {
    return { items: this.catalogue.getChapters(id) };
  }

  @Get('titles/:id/tracks')
  getTracks(@Param('id') id: string) {
    return { items: this.catalogue.getTracks(id) };
  }

  @Get('categories')
  listCategories() {
    return { items: this.catalogue.listCategories() };
  }

  @Get('collections')
  listCollections() {
    return { items: this.catalogue.listCollections() };
  }

  @Get('collections/:id')
  getCollection(@Param('id') id: string) {
    return this.catalogue.getCollection(id);
  }
}
