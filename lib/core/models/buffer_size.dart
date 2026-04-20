/// Buffer size options for streaming
enum BufferSize {
  small,
  medium,
  large,
  veryLarge,
  extraLarge, // For very unstable connections
}

extension BufferSizeExtension on BufferSize {
  String get displayName {
    switch (this) {
      case BufferSize.small:
        return 'Small (3s)';
      case BufferSize.medium:
        return 'Medium (5s)';
      case BufferSize.large:
        return 'Large (15s)';
      case BufferSize.veryLarge:
        return 'Very Large (30s)';
      case BufferSize.extraLarge:
        return 'Extra Large (60s)';
    }
  }

  int get durationSeconds {
    switch (this) {
      case BufferSize.small:
        return 3;
      case BufferSize.medium:
        return 5;
      case BufferSize.large:
        return 15;
      case BufferSize.veryLarge:
        return 30;
      case BufferSize.extraLarge:
        return 60;
    }
  }

  /// Minimum seconds to buffer before resuming playback after a stall
  int get minBufferBeforeResume {
    switch (this) {
      case BufferSize.small:
        return 1;
      case BufferSize.medium:
        return 2;
      case BufferSize.large:
        return 5;
      case BufferSize.veryLarge:
        return 10;
      case BufferSize.extraLarge:
        return 15;
    }
  }

  String get description {
    switch (this) {
      case BufferSize.small:
        return 'Low latency, may buffer more';
      case BufferSize.medium:
        return 'Balanced latency and stability';
      case BufferSize.large:
        return 'More stable, higher latency';
      case BufferSize.veryLarge:
        return 'Most stable for slow connections';
      case BufferSize.extraLarge:
        return 'Maximum stability for very unstable connections';
    }
  }
}
