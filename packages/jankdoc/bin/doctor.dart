/// JankDoc doctor — checks the local install and prints actionable fixes.
///
/// Usage:
///   dart run jankdoc:doctor
///
/// Exits 0 if everything is healthy, 1 if any check failed.
library;

import 'dart:io';

import '../lib/src/doctor.dart';

Future<void> main(List<String> args) async {
  final doctor = Doctor();
  final results = await doctor.run();
  Doctor.report(results);
  exit(Doctor.exitCode(results));
}
