import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/services/env_service.dart';

void main() {
  group('EnvService.parseEnvLine', () {
    test('parses plain, quoted, export, and commented lines', () {
      expect(EnvService.parseEnvLine('DB_HOST=localhost'),
          equals(('DB_HOST', 'localhost')));
      expect(EnvService.parseEnvLine('export DB_PORT=5432'),
          equals(('DB_PORT', '5432')));
      expect(EnvService.parseEnvLine('DB_NAME="my app"'),
          equals(('DB_NAME', 'my app')));
      expect(EnvService.parseEnvLine("API_KEY='secret'"),
          equals(('API_KEY', 'secret')));
      expect(EnvService.parseEnvLine('  FOO = bar '),
          equals(('FOO', 'bar')));
      expect(EnvService.parseEnvLine('URL=http://x:1/y # comment'),
          equals(('URL', 'http://x:1/y')));
      expect(EnvService.parseEnvLine('# comment'), isNull);
      expect(EnvService.parseEnvLine(''), isNull);
      expect(EnvService.parseEnvLine('NOTANASSIGNMENT'), isNull);
    });
  });

  group('EnvService.load', () {
    late Directory tempProject;

    setUp(() {
      tempProject = Directory.systemTemp.createTempSync('vibe_env_');
    });

    tearDown(() {
      try {
        tempProject.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('loads .env and .env.local with local winning', () async {
      File('${tempProject.path}/.env').writeAsStringSync('A=1\nB=two\n');
      File('${tempProject.path}/.env.local')
          .writeAsStringSync('B=overridden\nC="three"\n');
      final env = EnvService();
      await env.load(tempProject.path);
      expect(env.vars['A'], '1');
      expect(env.vars['B'], 'overridden');
      expect(env.vars['C'], 'three');
      expect(env.envCount, 3);
      env.dispose();
    });

    test('detects databases from deps, prisma schema, env URLs, and compose',
        () async {
      File('${tempProject.path}/package.json').writeAsStringSync(
        '{"dependencies": {"express": "1", "pg": "1", "redis": "1", '
        '"mongoose": "1"}, "devDependencies": {"prisma": "1"}}\n',
      );
      File('${tempProject.path}/.env')
          .writeAsStringSync('DATABASE_URL=postgres://user:pw@db:5432/app\n');
      File('${tempProject.path}/prisma/schema.prisma').createSync(recursive: true);
      File('${tempProject.path}/prisma/schema.prisma')
          .writeAsStringSync('datasource db { provider = "postgres" }\n');
      File('${tempProject.path}/compose.yaml')
          .writeAsStringSync('services:\n  db:\n    image: postgres:16\n');

      final env = EnvService();
      await env.load(tempProject.path);
      expect(env.databases, contains('postgres'));
      expect(env.databases, contains('redis'));
      expect(env.databases, contains('mongodb'));
      expect(env.databases, contains('prisma'));
      expect(env.composeFile, isNotNull);
      env.dispose();
    });

    test('finds nothing in an empty project', () async {
      final env = EnvService();
      await env.load(tempProject.path);
      expect(env.vars, isEmpty);
      expect(env.databases, isEmpty);
      expect(env.composeFile, isNull);
      env.dispose();
    });

    test('extracts tables and columns from prisma schema and SQL migrations',
        () async {
      Directory('${tempProject.path}/prisma').createSync();
      File('${tempProject.path}/prisma/schema.prisma').writeAsStringSync('''
model User {
  id    Int    @id @default(autoincrement())
  name  String
  email String @unique
  @@map("users")
}

model Post {
  id      Int    @id
  title   String
  author  Int
  @@index([author])
}
''');
      Directory('${tempProject.path}/migrations/001').createSync(recursive: true);
      File('${tempProject.path}/migrations/001/init.sql').writeAsStringSync('''
CREATE TABLE "users" (
  "id" SERIAL PRIMARY KEY,
  "name" VARCHAR(255) NOT NULL,
  "email" VARCHAR(255) UNIQUE
);
''');

      final env = EnvService();
      await env.load(tempProject.path);
      expect(env.tables.map((t) => t.name), containsAll(['User', 'Post', 'users']));
      final users = env.tables.firstWhere((t) => t.name == 'users');
      expect(users.columns, containsAll(['id', 'name', 'email']));
      final post = env.tables.firstWhere((t) => t.name == 'Post');
      expect(post.columns, contains('author'));
      expect(post.columns, isNot(contains('@@index')));
      env.dispose();
    });
  });
}
