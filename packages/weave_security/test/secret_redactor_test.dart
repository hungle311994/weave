import 'package:test/test.dart';
import 'package:weave_security/weave_security.dart';

void main() {
  final SecretRedactor redactor = SecretRedactor();

  test('redacts well-known token formats', () {
    final List<String> secrets = <String>[
      'sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123',
      'sk-proj-abcdefghijklmnopqrstuvwxyz0123',
      'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
      'github_pat_11ABCDEFG0123456789_abcdefghijklmnop',
      'AKIAIOSFODNN7EXAMPLE',
      'xoxb-1234567890-abcdefghij',
      'AIzaSyA1234567890abcdefghijklmnopqrstuv',
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop',
    ];

    for (final String secret in secrets) {
      final String output = redactor.redact('value: $secret end');
      expect(output, isNot(contains(secret)), reason: secret);
      expect(output, contains(SecretRedactor.placeholder));
      expect(output, endsWith(' end'));
    }
  });

  test('redacts private key blocks across lines', () {
    const String key =
        '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAB3NzaC1yc2E\nmore\n'
        '-----END OPENSSH PRIVATE KEY-----';

    expect(redactor.redact('before\n$key\nafter'), 'before\n[REDACTED]\nafter');
  });

  test('keeps the label of bearer tokens and URL credentials', () {
    expect(redactor.redact('Authorization: Bearer abc.def-ghi_jkl.mnopqrstu'), 'Authorization: Bearer [REDACTED]');
    expect(redactor.redact('remote https://user:hunter2pass@github.com/x.git'), 'remote https://user:[REDACTED]@github.com/x.git');
  });

  test('redacts literal credential assignments but not code', () {
    expect(redactor.redact('PASSWORD=correct-horse-battery'), 'PASSWORD=[REDACTED]');
    expect(redactor.redact('api_key: "abcd1234efgh5678"'), 'api_key: "[REDACTED]"');
    expect(redactor.redact('final token = readToken();'), 'final token = readToken();');
    expect(redactor.redact('token: short'), 'token: short');
  });

  test('redacts values of credential environment variables', () {
    final SecretRedactor fromEnvironment = SecretRedactor.fromEnvironment(<String, String>{'OPENAI_API_KEY': 'custom-secret-value-1', 'MY_SERVICE_TOKEN': 'another-secret-2', 'HOME': '/Users/someone', 'SHORT_TOKEN': 'abc'});

    final String output = fromEnvironment.redact('using custom-secret-value-1 and another-secret-2 in /Users/someone');

    expect(output, 'using [REDACTED] and [REDACTED] in /Users/someone');
    expect(fromEnvironment.redact('abc'), 'abc');
  });

  test('preserves text without secrets exactly', () {
    const String text = '  indented\n\ttabbed line  \n';
    expect(redactor.redact(text), text);
  });
}
