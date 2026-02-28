import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/presentation/providers/player_provider.dart';

void main() {
  group('PlayerState', () {
    test('should have correct default values', () {
      const state = PlayerState();

      expect(state.isPlaying, false);
      expect(state.isBuffering, false);
      expect(state.isPrebuffering, false);
      expect(state.isReconnecting, false);
      expect(state.isFullscreen, false);
      expect(state.volume, 1.0);
      expect(state.isMuted, false);
      expect(state.position, Duration.zero);
      expect(state.duration, Duration.zero);
      expect(state.bufferedDuration, Duration.zero);
      expect(state.error, null);
      expect(state.videoTracks, isEmpty);
      expect(state.audioTracks, isEmpty);
      expect(state.subtitleTracks, isEmpty);
      expect(state.currentVideoTrack, null);
      expect(state.currentAudioTrack, null);
      expect(state.currentSubtitleTrack, null);
      expect(state.playbackSpeed, 1.0);
      expect(state.aspectRatioMode, AspectRatioMode.auto);
      expect(state.bufferSize, BufferSize.medium);
      expect(state.retryAttempt, 0);
      expect(state.maxRetries, 3);
    });

    group('copyWith', () {
      test('should update isPlaying', () {
        const state = PlayerState();
        final newState = state.copyWith(isPlaying: true);

        expect(newState.isPlaying, true);
        expect(newState.volume, 1.0); // unchanged
      });

      test('should update multiple properties', () {
        const state = PlayerState();
        final newState = state.copyWith(
          isPlaying: true,
          isBuffering: true,
          volume: 0.5,
        );

        expect(newState.isPlaying, true);
        expect(newState.isBuffering, true);
        expect(newState.volume, 0.5);
        expect(newState.isFullscreen, false); // unchanged
      });

      test('should update error', () {
        const state = PlayerState();
        final newState = state.copyWith(error: 'Test error');

        expect(newState.error, 'Test error');
      });

      test('should clear error when null passed', () {
        final state = const PlayerState().copyWith(error: 'Test error');
        final clearedState = state.copyWith(clearError: true);

        expect(clearedState.error, null);
      });

      test('should update tracks', () {
        const state = PlayerState();
        final videoTracks = [
          const TrackInfo(id: '1', title: 'HD', width: 1920, height: 1080),
          const TrackInfo(id: '2', title: 'SD', width: 1280, height: 720),
        ];
        final newState = state.copyWith(videoTracks: videoTracks);

        expect(newState.videoTracks.length, 2);
        expect(newState.videoTracks[0].id, '1');
        expect(newState.videoTracks[0].title, 'HD');
      });

      test('should update position and duration', () {
        const state = PlayerState();
        final newState = state.copyWith(
          position: const Duration(minutes: 5),
          duration: const Duration(hours: 1),
        );

        expect(newState.position, const Duration(minutes: 5));
        expect(newState.duration, const Duration(hours: 1));
      });

      test('should update playback speed', () {
        const state = PlayerState();
        final newState = state.copyWith(playbackSpeed: 1.5);

        expect(newState.playbackSpeed, 1.5);
      });

      test('should update aspect ratio mode', () {
        const state = PlayerState();
        final newState = state.copyWith(aspectRatioMode: AspectRatioMode.ratio16x9);

        expect(newState.aspectRatioMode, AspectRatioMode.ratio16x9);
      });

      test('should update reconnecting state', () {
        const state = PlayerState();
        final newState = state.copyWith(
          isReconnecting: true,
          retryAttempt: 2,
        );

        expect(newState.isReconnecting, true);
        expect(newState.retryAttempt, 2);
        expect(newState.maxRetries, 3); // unchanged default
      });

      test('should update buffer size', () {
        const state = PlayerState();
        final newState = state.copyWith(bufferSize: BufferSize.large);

        expect(newState.bufferSize, BufferSize.large);
      });
    });
  });

  group('TrackInfo', () {
    test('should create with required id', () {
      const track = TrackInfo(id: 'track1');

      expect(track.id, 'track1');
      expect(track.title, null);
      expect(track.language, null);
    });

    test('should create with all properties', () {
      const track = TrackInfo(
        id: 'video1',
        title: 'HD Video',
        language: 'English',
        codec: 'h264',
        width: 1920,
        height: 1080,
        bitrate: 5000000,
      );

      expect(track.id, 'video1');
      expect(track.title, 'HD Video');
      expect(track.language, 'English');
      expect(track.codec, 'h264');
      expect(track.width, 1920);
      expect(track.height, 1080);
      expect(track.bitrate, 5000000);
    });

    group('displayName', () {
      test('should return title if present', () {
        const track = TrackInfo(id: '1', title: 'English (Stereo)');
        expect(track.displayName, 'English (Stereo)');
      });

      test('should return language if title is absent', () {
        const track = TrackInfo(id: '1', language: 'Spanish');
        expect(track.displayName, 'Spanish');
      });

      test('should return resolution if title and language absent', () {
        const track = TrackInfo(id: '1', width: 1920, height: 1080);
        expect(track.displayName, '1920x1080');
      });

      test('should return codec if only codec available', () {
        const track = TrackInfo(id: '1', codec: 'AAC');
        expect(track.displayName, 'AAC');
      });

      test('should return Track id as fallback', () {
        const track = TrackInfo(id: '1');
        expect(track.displayName, 'Track 1');
      });

      test('should prefer title over language', () {
        const track = TrackInfo(id: '1', title: 'Main Audio', language: 'English');
        expect(track.displayName, 'Main Audio');
      });

      test('should prefer language over resolution', () {
        const track = TrackInfo(id: '1', language: 'French', width: 1920, height: 1080);
        expect(track.displayName, 'French');
      });

      test('should handle empty title string', () {
        const track = TrackInfo(id: '1', title: '', language: 'German');
        expect(track.displayName, 'German');
      });
    });
  });

  group('AspectRatioMode', () {
    group('displayName', () {
      test('should return correct display names', () {
        expect(AspectRatioMode.auto.displayName, 'Auto');
        expect(AspectRatioMode.fit.displayName, 'Fit');
        expect(AspectRatioMode.fill.displayName, 'Fill');
        expect(AspectRatioMode.ratio16x9.displayName, '16:9');
        expect(AspectRatioMode.ratio4x3.displayName, '4:3');
        expect(AspectRatioMode.ratio21x9.displayName, '21:9');
      });
    });

    group('aspectRatio', () {
      test('should return null for auto, fit, fill', () {
        expect(AspectRatioMode.auto.aspectRatio, null);
        expect(AspectRatioMode.fit.aspectRatio, null);
        expect(AspectRatioMode.fill.aspectRatio, null);
      });

      test('should return correct ratio for 16:9', () {
        expect(AspectRatioMode.ratio16x9.aspectRatio, closeTo(16 / 9, 0.001));
      });

      test('should return correct ratio for 4:3', () {
        expect(AspectRatioMode.ratio4x3.aspectRatio, closeTo(4 / 3, 0.001));
      });

      test('should return correct ratio for 21:9', () {
        expect(AspectRatioMode.ratio21x9.aspectRatio, closeTo(21 / 9, 0.001));
      });
    });

    test('should have all expected values', () {
      expect(AspectRatioMode.values.length, 6);
      expect(AspectRatioMode.values.contains(AspectRatioMode.auto), true);
      expect(AspectRatioMode.values.contains(AspectRatioMode.fit), true);
      expect(AspectRatioMode.values.contains(AspectRatioMode.fill), true);
      expect(AspectRatioMode.values.contains(AspectRatioMode.ratio16x9), true);
      expect(AspectRatioMode.values.contains(AspectRatioMode.ratio4x3), true);
      expect(AspectRatioMode.values.contains(AspectRatioMode.ratio21x9), true);
    });
  });

  group('BufferSize', () {
    group('displayName', () {
      test('should return correct display names', () {
        expect(BufferSize.small.displayName, 'Small (1s)');
        expect(BufferSize.medium.displayName, 'Medium (5s)');
        expect(BufferSize.large.displayName, 'Large (15s)');
        expect(BufferSize.veryLarge.displayName, 'Very Large (30s)');
        expect(BufferSize.extraLarge.displayName, 'Extra Large (60s)');
      });
    });

    group('durationSeconds', () {
      test('should return correct durations', () {
        expect(BufferSize.small.durationSeconds, 1);
        expect(BufferSize.medium.durationSeconds, 5);
        expect(BufferSize.large.durationSeconds, 15);
        expect(BufferSize.veryLarge.durationSeconds, 30);
        expect(BufferSize.extraLarge.durationSeconds, 60);
      });
    });

    group('minBufferBeforeResume', () {
      test('should return correct minimum buffer values', () {
        expect(BufferSize.small.minBufferBeforeResume, 1);
        expect(BufferSize.medium.minBufferBeforeResume, 2);
        expect(BufferSize.large.minBufferBeforeResume, 5);
        expect(BufferSize.veryLarge.minBufferBeforeResume, 10);
        expect(BufferSize.extraLarge.minBufferBeforeResume, 15);
      });
    });

    group('description', () {
      test('should return descriptions', () {
        expect(BufferSize.small.description, isNotEmpty);
        expect(BufferSize.medium.description, isNotEmpty);
        expect(BufferSize.large.description, isNotEmpty);
        expect(BufferSize.veryLarge.description, isNotEmpty);
        expect(BufferSize.extraLarge.description, isNotEmpty);
      });
    });

    test('should have all expected values', () {
      expect(BufferSize.values.length, 5);
      expect(BufferSize.values.contains(BufferSize.small), true);
      expect(BufferSize.values.contains(BufferSize.medium), true);
      expect(BufferSize.values.contains(BufferSize.large), true);
      expect(BufferSize.values.contains(BufferSize.veryLarge), true);
      expect(BufferSize.values.contains(BufferSize.extraLarge), true);
    });
  });
}
