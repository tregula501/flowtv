// Chromecast service with platform-specific implementations
// Android/iOS use flutter_chrome_cast, other platforms use stub

export 'cast_service_stub.dart'
    if (dart.library.io) 'cast_service_impl.dart';
