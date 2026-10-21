import 'dart:convert';
import 'dart:typed_data';

/// One file of a melody model release (D24 manifest entry).
class ModelFile {
  const ModelFile({
    required this.name,
    required this.bytes,
    required this.sha256,
  });

  final String name;
  final int bytes;
  final String sha256;
}

/// The release manifest bundled with the app
/// (`tools/melody-model/releases/melody-model-v1.json`, copied by
/// tools/sync_content.py). It is the trust root: downloaded bytes are used
/// only when their sha256 matches it. See docs/specs/practice-mode.md.
class ModelManifest {
  const ModelManifest({
    required this.tag,
    required this.urlTemplate,
    required this.files,
    required this.config,
  });

  /// Files the browser runtime needs (the checkpoint and configs are not).
  static const runtimeFiles = [
    'decoder.int8.onnx',
    'heads.int8.onnx',
    'vocab.json',
  ];

  factory ModelManifest.fromJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final files = <String, ModelFile>{
      for (final e in (j['files'] as Map<String, dynamic>).entries)
        e.key: ModelFile(
          name: e.key,
          bytes: (e.value['bytes'] as num).toInt(),
          sha256: (e.value['sha256'] as String).toLowerCase(),
        ),
    };
    for (final f in runtimeFiles) {
      if (files[f] == null) throw FormatException('manifest has no $f');
    }
    final model =
        (j['training'] as Map<String, dynamic>)['model']
            as Map<String, dynamic>;
    return ModelManifest(
      tag: j['tag'] as String,
      urlTemplate: j['url'] as String,
      files: files,
      config: {
        for (final k in const ['layers', 'heads', 'd'])
          k: (model[k] as num).toInt(),
      },
    );
  }

  final String tag;
  final String urlTemplate;
  final Map<String, ModelFile> files;

  /// Decoder shape for the KV cache: layers, heads, d.
  final Map<String, int> config;

  int get runtimeBytes => runtimeFiles.fold(0, (a, f) => a + files[f]!.bytes);

  /// Download URL of [file]: [base] (`--dart-define=MELODY_MODEL_URL`) is a
  /// template with `{file}` or a directory URL; empty means the release URL.
  String urlFor(String file, {String base = ''}) {
    final t = base.isEmpty ? urlTemplate : base;
    if (t.contains('{file}')) return t.replaceAll('{file}', file);
    return t.endsWith('/') ? '$t$file' : '$t/$file';
  }
}

/// A downloaded file failed its sha256 check; it is never used or cached.
class ModelIntegrityError implements Exception {
  ModelIntegrityError(this.file, this.want, this.got);

  final String file;
  final String want;
  final String got;

  @override
  String toString() => '$file: sha256 $got does not match the manifest ($want)';
}

/// Platform IO for [ModelStore]; the web version uses fetch, Cache Storage
/// and crypto.subtle (tune_generator_web.dart).
abstract class ModelIo {
  /// GET [url]; [onBytes] reports bytes received so far.
  Future<Uint8List> fetch(String url, void Function(int received) onBytes);
  Future<String> sha256(Uint8List bytes);

  /// Cached bytes under [key], or null.
  Future<Uint8List?> cacheGet(String key);
  Future<void> cachePut(String key, Uint8List bytes);
  Future<void> cacheDelete(String key);
}

/// Loads the runtime files: from the cache when present, else downloaded with
/// progress; in both cases verified against the manifest before use.
class ModelStore {
  ModelStore(this.manifest, this.io, {this.baseUrl = ''});

  final ModelManifest manifest;
  final ModelIo io;
  final String baseUrl;

  /// Cache key: content-addressed, so a new manifest never reuses old bytes.
  static String cacheKey(ModelFile f) => 'melody-model/${f.sha256}/${f.name}';

  /// [onProgress] gets 0..1 of the runtime bytes; cached files count at once.
  Future<Map<String, Uint8List>> load({
    void Function(double fraction)? onProgress,
  }) async {
    final total = manifest.runtimeBytes;
    var done = 0;
    final out = <String, Uint8List>{};
    for (final name in ModelManifest.runtimeFiles) {
      final f = manifest.files[name]!;
      final key = cacheKey(f);
      var bytes = await io.cacheGet(key);
      if (bytes != null && await io.sha256(bytes) != f.sha256) {
        await io.cacheDelete(key); // corrupted or tampered: fetch again
        bytes = null;
      }
      if (bytes == null) {
        final base = done;
        final got = await io.fetch(
          manifest.urlFor(name, base: baseUrl),
          (r) => onProgress?.call(((base + r) / total).clamp(0, 1)),
        );
        final hash = await io.sha256(got);
        if (hash != f.sha256) throw ModelIntegrityError(name, f.sha256, hash);
        try {
          await io.cachePut(key, got);
        } catch (_) {
          // No cache (private window, quota): still usable this session.
        }
        bytes = got;
      }
      done += f.bytes;
      onProgress?.call((done / total).clamp(0, 1));
      out[name] = bytes;
    }
    return out;
  }
}
