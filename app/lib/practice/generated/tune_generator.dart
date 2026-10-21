import 'practice_service.dart';
import 'tune_generator_stub.dart'
    if (dart.library.js_interop) 'tune_generator_web.dart'
    as impl;

/// Model files URL: `--dart-define=MELODY_MODEL_URL=<dir or template with
/// {file}>`. Default `melody/model/` on the app's own origin (staged by
/// tools/melody-model/web/stage_app_model.py); see docs/specs/practice-mode.md.
const melodyModelUrl = String.fromEnvironment(
  'MELODY_MODEL_URL',
  defaultValue: 'melody/model/',
);

/// The platform's generator. [manifestJson] is the bundled release manifest.
TuneGenerator createTuneGenerator(String manifestJson) =>
    impl.createTuneGenerator(manifestJson, melodyModelUrl);
