import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/services/project_service.dart';

void main() {
  GitignoreMatcher m(List<String> lines) => GitignoreMatcher(lines);

  group('GitignoreMatcher', () {
    test('bare name matches any path segment at any depth', () {
      final gi = m(['start.sh']);
      expect(gi.isIgnored('start.sh', isDir: false), isTrue);
      expect(gi.isIgnored('.vibestudio/scripts/start.sh', isDir: false), isTrue);
      expect(gi.isIgnored('src/start.sh', isDir: false), isTrue);
      expect(gi.isIgnored('src/app.dart', isDir: false), isFalse);
    });

    test('trailing slash matches only directories', () {
      final gi = m(['.vibestudio/']);
      expect(gi.isIgnored('.vibestudio', isDir: true), isTrue);
      expect(gi.isIgnored('.vibestudio/scripts/start.sh', isDir: false), isTrue);
      expect(gi.isIgnored('.vibestudio.sh', isDir: false), isFalse);
    });

    test('anchored pattern only matches from root', () {
      final gi = m(['/dist']);
      expect(gi.isIgnored('dist', isDir: true), isTrue);
      expect(gi.isIgnored('a/b/dist', isDir: true), isFalse);
    });

    test('glob star and question mark', () {
      final gi = m(['*.log', '?.env']);
      expect(gi.isIgnored('error.log', isDir: false), isTrue);
      expect(gi.isIgnored('logs/error.log', isDir: false), isTrue);
      expect(gi.isIgnored('x.env', isDir: false), isTrue);
      expect(gi.isIgnored('.env', isDir: false), isFalse);
      expect(gi.isIgnored('prod.env', isDir: false), isFalse);
      expect(gi.isIgnored('app.dart', isDir: false), isFalse);
    });

    test('double star matches across directories', () {
      final gi = m(['**/node_modules/']);
      expect(gi.isIgnored('node_modules', isDir: true), isTrue);
      expect(gi.isIgnored('a/b/node_modules', isDir: true), isTrue);
    });

    test('slash pattern matches relative path anywhere', () {
      final gi = m(['.vibestudio/scripts/start.sh']);
      expect(gi.isIgnored('.vibestudio/scripts/start.sh', isDir: false), isTrue);
    });

    test('comments and empty lines are skipped', () {
      final gi = m(['# a comment', '', '  ', 'start.sh']);
      expect(gi.isIgnored('start.sh', isDir: false), isTrue);
    });

    test('negation re-includes a matched file', () {
      final gi = m(['*.sh', '!keep.sh']);
      expect(gi.isIgnored('run.sh', isDir: false), isTrue);
      expect(gi.isIgnored('keep.sh', isDir: false), isFalse);
    });
  });
}
