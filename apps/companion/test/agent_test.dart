import 'package:flutter_test/flutter_test.dart';
import '../../../scripts/check-agent.dart' as checks;

void main() {
  test(
    'agent protocol, tool guards, context budget and native persistence',
    checks.main,
  );
}
