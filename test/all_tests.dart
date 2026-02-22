// FlowTV Comprehensive Test Suite
//
// Run all tests with: flutter test test/all_tests.dart
// Run specific test file: flutter test test/unit/data/m3u_parser_test.dart

import 'package:flutter_test/flutter_test.dart';

// Import all unit test files
import 'unit/data/m3u_parser_test.dart' as m3u_parser_test;
import 'unit/data/xmltv_parser_test.dart' as xmltv_parser_test;
import 'unit/data/models_test.dart' as models_test;
import 'unit/data/xtream_api_test.dart' as xtream_api_test;
import 'unit/core/string_extensions_test.dart' as string_extensions_test;
import 'unit/core/datetime_extensions_test.dart' as datetime_extensions_test;
import 'unit/presentation/player_provider_test.dart' as player_provider_test;
import 'unit/presentation/multiview_provider_test.dart' as multiview_provider_test;
import 'unit/presentation/progress_state_test.dart' as progress_state_test;

void main() {
  group('FlowTV Unit Tests', () {
    group('Data Layer', () {
      m3u_parser_test.main();
      xmltv_parser_test.main();
      models_test.main();
      xtream_api_test.main();
    });

    group('Core', () {
      string_extensions_test.main();
      datetime_extensions_test.main();
    });

    group('Presentation', () {
      player_provider_test.main();
      multiview_provider_test.main();
      progress_state_test.main();
    });
  });
}
