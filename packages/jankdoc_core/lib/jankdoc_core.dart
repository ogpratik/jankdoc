/// JankDoc core models, interfaces, and domain types.
///
/// This package is the dependency root — it imports nothing from other
/// JankDoc packages. All other packages depend on this one.
library jankdoc_core;

// Models
export 'src/models/diagnosis.dart';
export 'src/models/jank_frame.dart';
export 'src/models/rule.dart';
export 'src/models/session.dart';
export 'src/models/telemetry_batch.dart';

// Interfaces
export 'src/interfaces/llm_provider.dart';
export 'src/interfaces/rule_provider.dart';
export 'src/interfaces/vector_store.dart';
