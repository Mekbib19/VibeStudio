import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/services/port_service.dart';

void main() {
  group('PortService.parseSs', () {
    const out = '''
State    Recv-Q   Send-Q   Local Address:Port    Peer Address:Port   Process
LISTEN   0       4096     127.0.0.1:5432        0.0.0.0:*           users:(("postgres",pid=1234,fd=6))
LISTEN   0       511      [::]:3000             [::]:*              users:(("node",pid=4242,fd=24))
LISTEN   0       511      *:8080                *:*                 users:(("server",pid=99,fd=3))
''';
    test('parses ports, pids and commands', () {
      final ports = PortService.parseSs(out);
      expect(ports.map((p) => p.port), [5432, 3000, 8080]);
      expect(ports.map((p) => p.pid), [1234, 4242, 99]);
      expect(ports.map((p) => p.command), ['postgres', 'node', 'server']);
    });
  });

  group('PortService.parseLsof', () {
    const out = '''
COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
node    4242 root   24u  IPv6 12345      0t0  TCP *:3000 (LISTEN)
server  4243 root   25u  IPv4 12346      0t0  TCP 127.0.0.1:5432 (LISTEN)
''';
    test('parses ports, pids and commands', () {
      final ports = PortService.parseLsof(out);
      expect(ports.map((p) => p.port), [3000, 5432]);
      expect(ports.map((p) => p.pid), [4242, 4243]);
      expect(ports.map((p) => p.command), ['node', 'server']);
    });
  });

  group('PortService.portFromToken', () {
    test('handles ipv4, ipv6 and wildcard', () {
      expect(PortService.portFromToken('127.0.0.1:5432'), 5432);
      expect(PortService.portFromToken('[::]:3000'), 3000);
      expect(PortService.portFromToken('[::1]:8080'), 8080);
      expect(PortService.portFromToken('*:9000'), 9000);
      expect(PortService.portFromToken('0.0.0.0:7000'), 7000);
      expect(PortService.portFromToken('no-port-here'), isNull);
    });
  });
}
