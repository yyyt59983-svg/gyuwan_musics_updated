// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final YoutubeExplode ytExplode = YoutubeExplode();

// Try multiple clients in order - if one is blocked, fallback to next
final _clientFallbacks = [
  [YoutubeApiClient.androidVr],
  [YoutubeApiClient.ios],
  [YoutubeApiClient.android],
  [YoutubeApiClient.mweb],
];

Future<AudioSource> getYouTubeAudioSource({
  required String videoId,
  required String quality,
  Object? tag,
}) async {
  Exception? lastError;

  for (final clients in _clientFallbacks) {
    try {
      debugPrint('[YT Stream] Trying clients: $clients for $videoId');
      final manifest = await ytExplode.videos.streams.getManifest(
        videoId,
        requireWatchPage: true,
        ytClients: clients,
      );
      final supportedStreams = manifest.audioOnly.sortByBitrate();

      // sortByBitrate: ascending order, so last = highest bitrate
      final audioStream = quality == 'high'
          ? supportedStreams.lastOrNull
          : supportedStreams.firstOrNull;

      if (audioStream == null) {
        throw Exception('No audio streams found for video $videoId');
      }

      debugPrint('[YT Stream] Got stream URL for $videoId (${audioStream.bitrate})');
      return AudioSource.uri(audioStream.url, tag: tag);
    } catch (e) {
      debugPrint('[YT Stream] Client $clients failed: $e');
      lastError = Exception('Failed with clients $clients: $e');
      continue;
    }
  }

  throw lastError ?? Exception('All clients failed for video $videoId');
}
