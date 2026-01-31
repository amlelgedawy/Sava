import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ValidationPipe } from '@nestjs/common';
import { Logger } from '@nestjs/common';
import helmet from 'helmet';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // app.use(helmet());
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  app.enableCors({
    origin: true,
    credentials: true,
  });
  app.useLogger(['log', 'error', 'warn', 'debug', 'verbose']);

  // const server = app.getHttpServer();
   // const router = server._events.request._router;
  // console.log(
  //   'ROUTES:',
  //   router.stack
  //     .filter((l) => l.route)
  //     .map(
  //       (l) =>
  //         `${Object.keys(l.route.methods)[0].toUpperCase()} ${l.route.path}`,
  //     ),
  // );

  app.setGlobalPrefix('api');
  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
