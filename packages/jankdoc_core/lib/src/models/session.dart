import 'package:meta/meta.dart';
import 'telemetry_batch.dart';

/// A single JankDoc analysis run — from JankDoc.attach() to app termination.
@immutable
final class Session {
  const Session({
    required this.id,
    required this.projectFingerprint,
    required this.flutterVersion,
    required this.dartVersion,
    required this.deviceInfo,
    required this.startedAt,
    this.endedAt,
    this.diagnosisCount = 0,
  });

  /// UUID v4 session identifier.
  final String id;

  /// SHA-256 of the absolute pubspec.yaml path.
  /// Used to correlate sessions from the same project without storing paths.
  final String projectFingerprint;

  final String flutterVersion;
  final String dartVersion;
  final DeviceInfo deviceInfo;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Total diagnoses produced in this session.
  final int diagnosisCount;

  bool get isActive => endedAt == null;

  Duration? get duration =>
      endedAt != null ? endedAt!.difference(startedAt) : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_fingerprint': projectFingerprint,
        'flutter_version': flutterVersion,
        'dart_version': dartVersion,
        'device_info': deviceInfo.toJson(),
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        'diagnosis_count': diagnosisCount,
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        projectFingerprint: json['project_fingerprint'] as String,
        flutterVersion: json['flutter_version'] as String,
        dartVersion: json['dart_version'] as String,
        deviceInfo:
            DeviceInfo.fromJson(json['device_info'] as Map<String, dynamic>),
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: json['ended_at'] != null
            ? DateTime.parse(json['ended_at'] as String)
            : null,
        diagnosisCount: (json['diagnosis_count'] as int?) ?? 0,
      );
}
