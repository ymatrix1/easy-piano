import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'model_store.dart';
import 'practice_service.dart';

@JS('epMelodyImport')
external JSPromise<_Runtime> _import();

/// web/melody/practice.js, loaded on first use.
extension type _Runtime._(JSObject _) implements JSObject {
  external JSPromise<JSUint8Array> fetchBytes(JSString url, JSFunction onBytes);
  external JSPromise<JSString> sha256(JSUint8Array bytes);
  external JSPromise<JSUint8Array?> cacheGet(JSString key);
  external JSPromise<JSAny?> cachePut(JSString key, JSUint8Array bytes);
  external JSPromise<JSAny?> cacheDelete(JSString key);
  external JSPromise<JSAny?> load(
    JSUint8Array decoder,
    JSUint8Array heads,
    JSString vocab,
    JSString config,
  );
  external JSPromise<JSString> generateJson(
    JSString gen,
    JSNumber n,
    JSNumber seed,
    JSNumber temperature,
  );
}

TuneGenerator createTuneGenerator(String manifestJson, String baseUrl) =>
    WebTuneGenerator(manifestJson, baseUrl);

class _WebIo implements ModelIo {
  _WebIo(this.rt);

  final _Runtime rt;

  @override
  Future<Uint8List> fetch(String url, void Function(int) onBytes) async =>
      (await rt
              .fetchBytes(url.toJS, ((JSNumber n) => onBytes(n.toDartInt)).toJS)
              .toDart)
          .toDart;

  @override
  Future<String> sha256(Uint8List bytes) async =>
      (await rt.sha256(bytes.toJS).toDart).toDart;

  @override
  Future<Uint8List?> cacheGet(String key) async =>
      (await rt.cacheGet(key.toJS).toDart)?.toDart;

  @override
  Future<void> cachePut(String key, Uint8List bytes) =>
      rt.cachePut(key.toJS, bytes.toJS).toDart;

  @override
  Future<void> cacheDelete(String key) => rt.cacheDelete(key.toJS).toDart;
}

/// onnxruntime-web through web/melody/practice.js. The model is loaded once
/// per app session; the browser cache keeps the verified bytes across visits.
class WebTuneGenerator implements TuneGenerator {
  WebTuneGenerator(this.manifestJson, this.baseUrl);

  final String manifestJson;
  final String baseUrl;
  _Runtime? _rt;
  Future<void>? _ready;

  @override
  bool get supported => true;

  @override
  Future<void> prepare({void Function(double fraction)? onProgress}) =>
      _ready ??= _prepare(onProgress).catchError((Object e) {
        _ready = null; // allow a retry after a failed download
        throw e;
      });

  Future<void> _prepare(void Function(double)? onProgress) async {
    final rt = await _import().toDart;
    final manifest = ModelManifest.fromJson(manifestJson);
    final files = await ModelStore(
      manifest,
      _WebIo(rt),
      baseUrl: baseUrl,
    ).load(onProgress: onProgress);
    await rt
        .load(
          files['decoder.int8.onnx']!.toJS,
          files['heads.int8.onnx']!.toJS,
          utf8.decode(files['vocab.json']!).toJS,
          jsonEncode(manifest.config).toJS,
        )
        .toDart;
    _rt = rt;
  }

  @override
  Future<List<Candidate>> generate(
    Map<String, dynamic> gen, {
    required int n,
    required int seed,
    double temperature = 0.9,
  }) async {
    final rt = _rt;
    if (rt == null) throw StateError('prepare() first');
    final text = await rt
        .generateJson(jsonEncode(gen).toJS, n.toJS, seed.toJS, temperature.toJS)
        .toDart;
    return [
      for (final c in jsonDecode(text.toDart) as List)
        c as Map<String, dynamic>,
    ];
  }
}
