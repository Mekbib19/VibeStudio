import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/services/language_service.dart';
import 'package:vibe_studio/services/project_service.dart';

void main() {
  test('languageForPath recognizes common extensions', () {
    expect(languageForPath('/repo/lib/main.dart').name, 'Dart');
    expect(languageForPath('/repo/src/foo.cpp').name, 'C++');
    expect(languageForPath('/repo/src/foo.hpp').name, 'C++');
    expect(languageForPath('/repo/main.go').name, 'Go');
    expect(languageForPath('/repo/rust/src/lib.rs').name, 'Rust');
    expect(languageForPath('/repo/app.py').name, 'Python');
    expect(languageForPath('/repo/index.js').name, 'JavaScript');
    expect(languageForPath('/repo/app.tsx').name, 'TypeScript');
    expect(languageForPath('/repo/index.html').name, 'HTML');
    expect(languageForPath('/repo/style.css').name, 'CSS');
    expect(languageForPath('/repo/styles.scss').name, 'CSS');
    expect(languageForPath('/repo/app.vue').name, 'Vue');
    expect(languageForPath('/repo/data.json').name, 'JSON');
    expect(languageForPath('/repo/config.yaml').name, 'YAML');
    expect(languageForPath('/repo/Makefile').name, 'Make');
    expect(languageForPath('/repo/Dockerfile').name, 'Docker');
  });

  test('unknown files fall back to a generic language', () {
    expect(languageForPath('/repo/blob.zzz').name, 'File');
    expect(languageForPath('/repo/noext').name, 'File');
  });

  test('highlightModeForPath returns the highlight.js key', () {
    expect(highlightModeForPath('/a/main.dart'), 'dart');
    expect(highlightModeForPath('/a/app.tsx'), 'typescript');
    expect(highlightModeForPath('/a/x.html'), 'xml');
    expect(highlightModeForPath('/a/Dockerfile'), isNull);
  });

  test('detectProjectLanguage counts the dominant language', () {
    final nodes = [
      const FileNode(name: 'a.dart', path: '/p/a.dart', isDir: false),
      const FileNode(name: 'b.dart', path: '/p/b.dart', isDir: false),
      const FileNode(name: 'c.go', path: '/p/c.go', isDir: false),
    ];
    expect(detectProjectLanguage(nodes), 'Dart');
    expect(detectProjectLanguage(const []), isNull);
  });
}
