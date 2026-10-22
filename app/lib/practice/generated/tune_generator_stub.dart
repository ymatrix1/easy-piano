import 'practice_service.dart';

/// Native platforms: no ONNX runtime is wired yet (docs/specs/practice-mode.md).
TuneGenerator createTuneGenerator(String manifestJson, String baseUrl) =>
    _Unsupported();

class _Unsupported implements TuneGenerator {
  @override
  bool get supported => false;

  @override
  Future<void> prepare({void Function(double fraction)? onProgress}) =>
      throw UnsupportedError('practice mode runs on the web only for now');

  @override
  Future<List<Candidate>> generate(
    Map<String, dynamic> gen, {
    required int n,
    required int seed,
    double temperature = 0.9,
  }) => throw UnsupportedError('practice mode runs on the web only for now');
}
