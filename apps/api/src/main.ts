import 'dotenv/config';
import 'reflect-metadata';

import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';

import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableCors({
    origin: true,
    credentials: true,
  });
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(
    new ValidationPipe({
      // Prototype controllers use inline body types (not class-validator DTOs).
      // whitelist would strip undeclared fields and break Studio uploads.
      whitelist: false,
      transform: true,
      forbidUnknownValues: false,
    }),
  );

  const port = Number(process.env.PORT ?? 3001);
  // Bind all interfaces so the iOS Simulator can reach the host API via 127.0.0.1.
  await app.listen(port, '0.0.0.0');
  // eslint-disable-next-line no-console
  console.log(`Listen+ API listening on http://127.0.0.1:${port}/v1`);
}

void bootstrap();
