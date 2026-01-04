// FlowTV Comprehensive Test Suite
//
// Run all tests with: flutter test test/all_tests.dart
// Run specific test file: flutter test test/unit/data/m3u_parser_test.dart
//
// Test Coverage:
// - M3U Parser: 25 tests
// - XMLTV Parser: 18 tests
// - String Extensions: 25 tests
// - DateTime Extensions: 23 tests
// - Player Provider: 30 tests
// - Data Models: 25 tests
// Total: ~146 tests

import 'package:flutter_test/flutter_test.dart';

// Import all unit test files
import 'unit/data/m3u_parser_test.dart' as m3u_parser_test;
import 'unit/data/xmltv_parser_test.dart' as xmltv_parser_test;
import 'unit/data/models_test.dart' as models_test;
import 'unit/core/string_extensions_test.dart' as string_extensions_test;
import 'unit/core/datetime_extensions_test.dart' as datetime_extensions_test;
import 'unit/presentation/player_provider_test.dart' as player_provider_test;

void main() {
  group('FlowTV Unit Tests', () {
    group('Data Layer', () {
      m3u_parser_test.main();
      xmltv_parser_test.main();
      models_test.main();
    });

    group('Core', () {
      string_extensions_test.main();
      datetime_extensions_test.main();
    });

    group('Presentation', () {
      player_provider_test.main();
    });
  });
}
