import 'package:jankdoc_core/jankdoc_core.dart';

/// Validates every LLM-tier Diagnosis against the actual VM stack frames.
///
/// Prevents hallucinated file paths from reaching the user and destroying trust.
/// If the LLM cites a file that was not in the captured stack frames,
/// confidence is capped at 0.5 and the explanation is annotated.
final class OutputValidator {
  /// Validate [diagnosis] against [batch] and return a safe version.
  Diagnosis validate(Diagnosis diagnosis, TelemetryBatch batch) {
    if (diagnosis.tier != DiagnosisTier.llm) return diagnosis;
    if (diagnosis.rootCause.file == null) return diagnosis;

    final knownFiles = batch.jankFrames
        .expand((f) => [...f.uiStack, ...f.rasterStack])
        .map((s) => s.file)
        .toSet();

    final citedFile = diagnosis.rootCause.file!;
    final fileIsReal = knownFiles.any((f) => f.endsWith(citedFile) || citedFile.endsWith(f));

    if (!fileIsReal) {
      return diagnosis.copyWith(
        confidence: diagnosis.confidence.clamp(0.0, 0.5),
        explanation: '${diagnosis.explanation}\n\n'
            '⚠️ File attribution uncertain — `$citedFile` was not found in '
            'the captured stack frames. The root cause analysis may still be '
            'correct but the file/line reference could not be verified.',
      );
    }

    return diagnosis;
  }
}
