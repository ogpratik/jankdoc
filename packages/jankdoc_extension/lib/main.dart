import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/jankdoc_extension_app.dart';

void main() {
  runApp(
    const ProviderScope(
      child: DevToolsExtension(
        child: JankDocExtensionApp(),
      ),
    ),
  );
}
