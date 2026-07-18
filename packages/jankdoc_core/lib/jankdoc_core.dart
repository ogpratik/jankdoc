/// JankDoc core models, interfaces, and domain types.
///
/// This package is the dependency root — it imports nothing from other
/// JankDoc packages. All other packages depend on this one.
library jankdoc_core;

// Interfaces
export 'src/interfaces/kb_loader.dart';
export 'src/interfaces/kb_registry.dart';
export 'src/interfaces/llm_provider.dart';
export 'src/interfaces/rule_provider.dart';
export 'src/interfaces/vector_store.dart';

// Knowledge Base
export 'src/kb/kb_bundle.dart';
export 'src/kb/kb_category.dart';
export 'src/kb/kb_channel.dart';
export 'src/kb/kb_entry.dart';
export 'src/kb/kb_version.dart';

// Models
export 'src/models/diagnosis.dart';
export 'src/models/jank_frame.dart';
export 'src/models/rule.dart';
export 'src/models/session.dart';
export 'src/models/telemetry_batch.dart';

// Resolution
export 'src/resolution/resolution.dart';

// Rules
export 'src/rules/async_rules.dart';
export 'src/rules/build_rebuild_rules.dart';
export 'src/rules/builtin_rule_provider.dart';
export 'src/rules/impeller_rules.dart';
export 'src/rules/list_grid_rules.dart';
export 'src/rules/raster_rules.dart';
export 'src/rules/rule_engine.dart';
