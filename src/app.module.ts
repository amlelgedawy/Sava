import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { MongooseModule } from '@nestjs/mongoose';
import { mongoConfig } from './config/database.config';
import { ConfigModule, ConfigService  } from '@nestjs/config';
import { HealthController } from './common/health.controller';
import { AccelerometerModule } from './sensors/accelerometer/accelerometer.module';
import { UserModule } from './users/users.module';
import { EventsModule } from './events/events.module';
import { AlertsModule } from './alerts/alerts.module';


@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    MongooseModule.forRootAsync({
      imports:[ConfigModule],
      useFactory: (configService: ConfigService ) =>({
        uri: configService.get<string>('MONGO_URI'),
      }),
      inject: [ConfigService],
    }),
    AccelerometerModule,
    UserModule,
    EventsModule,
    AlertsModule,
    
  ],
  controllers: [AppController, HealthController],
  providers: [AppService],
})
export class AppModule {}
