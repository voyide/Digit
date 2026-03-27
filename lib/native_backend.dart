import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'engine.dart';

final class NativeRenderRequest extends ffi.Struct {
  @ffi.Uint64()
  external int startN;

  @ffi.Int32()
  external int bNum;
  @ffi.Int32()
  external int renderR;
  @ffi.Int32()
  external int renderC;
  @ffi.Int32()
  external int logicalR;
  @ffi.Int32()
  external int logicalC;
  @ffi.Int32()
  external int modM;
  @ffi.Int32()
  external int lhsRule;
  @ffi.Int32()
  external int rhs1Rule;
  @ffi.Int32()
  external int rhs2Rule;
  @ffi.Int32()
  external int logicOp;
  @ffi.Int32()
  external int postType;
  @ffi.Int32()
  external int iterK;
  @ffi.Int32()
  external int postGridR;
  @ffi.Int32()
  external int postGridC;
  @ffi.Int32()
  external int targetT;
  @ffi.Int32()
  external int modMc;
  @ffi.Int32()
  external int tupleK;
  @ffi.Int32()
  external int rowStart;
  @ffi.Int32()
  external int rowEnd;
}

typedef _RenderStripeNative = ffi.Int32 Function(
  ffi.Pointer<NativeRenderRequest>,
  ffi.Pointer<ffi.Uint32>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Int64,
);

typedef _RenderStripeDart = int Function(
  ffi.Pointer<NativeRenderRequest>,
  ffi.Pointer<ffi.Uint32>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _RenderPngFileNative = ffi.Int32 Function(
  ffi.Pointer<NativeRenderRequest>,
  ffi.Pointer<ffi.Uint32>,
  ffi.Pointer<ffi.Char>,
);

typedef _RenderPngFileDart = int Function(
  ffi.Pointer<NativeRenderRequest>,
  ffi.Pointer<ffi.Uint32>,
  ffi.Pointer<ffi.Char>,
);

class _NativeApi {
  final ffi.DynamicLibrary _lib;
  late final _RenderStripeDart renderStripe = _lib.lookupFunction<
      _RenderStripeNative, _RenderStripeDart>('render_stripe_rgba');
  late final _RenderPngFileDart renderPngFile = _lib.lookupFunction<
      _RenderPngFileNative, _RenderPngFileDart>('render_png_file');

  _NativeApi._(this._lib);

  static _NativeApi? _instance;

  static _NativeApi instance() {
    return _instance ??= _NativeApi._(_open());
  }

  static ffi.DynamicLibrary _open() {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Native backend is Android-only.');
    }
    return ffi.DynamicLibrary.open('libsequencer_native.so');
  }
}

int _postTypeCode(String postType) {
  switch (postType) {
    case 'NONE':
      return 0;
    case 'ITERATE':
      return 1;
    case 'C_SEQ':
      return 2;
    case 'D_SEQ':
      return 3;
    default:
      return 0;
  }
}

bool nativeBackendAvailable() {
  try {
    _NativeApi.instance();
    return true;
  } catch (_) {
    return false;
  }
}

bool canUseNativeForConfig(EngineConfig cfg) {
  if (!Platform.isAndroid) return false;
  if (cfg.postType != 'NONE') return false;
  if (!nativeBackendAvailable()) return false;

  final b = safeBase(cfg.bNum);
  if (b > 48) return false;

  final lhs = cfg.lhsRule;
  if ((lhs == 1 || lhs == 10 || lhs == 11 || (lhs >= 15 && lhs <= 18)) &&
      b > 36) {
    return false;
  }

  final span = cfg.logicalR * cfg.logicalC;
  final end = cfg.startN + BigInt.from(span + 1);
  if (end.bitLength > 64) return false;

  return true;
}

class NativeFileTaskArgs {
  final EngineConfig cfg;
  final String filePath;
  const NativeFileTaskArgs(this.cfg, this.filePath);
}

void _fillRequest(
  ffi.Pointer<NativeRenderRequest> ptr,
  EngineConfig cfg,
  int rowStart,
  int rowEnd,
) {
  ptr.ref.startN = cfg.startN.toInt();
  ptr.ref.bNum = safeBase(cfg.bNum);
  ptr.ref.renderR = cfg.renderR;
  ptr.ref.renderC = cfg.renderC;
  ptr.ref.logicalR = cfg.logicalR;
  ptr.ref.logicalC = cfg.logicalC;
  ptr.ref.modM = safeMod(cfg.modM);
  ptr.ref.lhsRule = cfg.lhsRule;
  ptr.ref.rhs1Rule = cfg.rhs1Rule;
  ptr.ref.rhs2Rule = cfg.rhs2Rule;
  ptr.ref.logicOp = cfg.logicOp;
  ptr.ref.postType = _postTypeCode(cfg.postType);
  ptr.ref.iterK = cfg.iterK;
  ptr.ref.postGridR = cfg.postGridR;
  ptr.ref.postGridC = cfg.postGridC;
  ptr.ref.targetT = cfg.targetT;
  ptr.ref.modMc = cfg.modMc;
  ptr.ref.tupleK = safeTupleK(cfg.tupleK);
  ptr.ref.rowStart = rowStart;
  ptr.ref.rowEnd = rowEnd;
}

String nativeExportPngTask(NativeFileTaskArgs args) {
  final api = _NativeApi.instance();
  final cfg = args.cfg;

  final reqPtr = calloc<NativeRenderRequest>();
  final palettePtr = calloc<ffi.Uint32>(cfg.palette.length);
  final pathPtr = args.filePath.toNativeUtf8().cast<ffi.Char>();

  try {
    _fillRequest(reqPtr, cfg, 0, cfg.renderR);

    final pal = palettePtr.asTypedList(cfg.palette.length);
    pal.setAll(0, cfg.palette);

    final code = api.renderPngFile(reqPtr, palettePtr, pathPtr);
    if (code != 0) {
      throw Exception('native render_png_file failed with code $code');
    }

    return args.filePath;
  } finally {
    calloc.free(reqPtr);
    calloc.free(palettePtr);
    calloc.free(pathPtr);
  }
}

void liveNativePreviewIsolate(List<dynamic> args) {
  final SendPort mainPort = args[0] as SendPort;
  final EngineConfig cfg = args[1] as EngineConfig;

  try {
    final api = _NativeApi.instance();
    final rowsPerChunk = math.min(64, math.max(24, cfg.renderR ~/ 20));

    for (int rowStart = 0; rowStart < cfg.renderR; rowStart += rowsPerChunk) {
      final rowEnd = math.min(cfg.renderR, rowStart + rowsPerChunk);
      final rows = rowEnd - rowStart;
      final byteLen = rows * cfg.renderC * 4;

      final reqPtr = calloc<NativeRenderRequest>();
      final palettePtr = calloc<ffi.Uint32>(cfg.palette.length);
      final outPtr = calloc<ffi.Uint8>(byteLen);

      try {
        _fillRequest(reqPtr, cfg, rowStart, rowEnd);
        final pal = palettePtr.asTypedList(cfg.palette.length);
        pal.setAll(0, cfg.palette);

        final code = api.renderStripe(reqPtr, palettePtr, outPtr, byteLen);
        if (code != 0) {
          throw Exception('native render_stripe_rgba failed with code $code');
        }

        final bytes = Uint8List.fromList(outPtr.asTypedList(byteLen));

        mainPort.send(
          RenderChunkMessage(
            renderId: cfg.renderId,
            rowStart: rowStart,
            rowCount: rows,
            width: cfg.renderC,
            progress: rowEnd / cfg.renderR,
            data: TransferableTypedData.fromList([bytes]),
          ),
        );
      } finally {
        calloc.free(reqPtr);
        calloc.free(palettePtr);
        calloc.free(outPtr);
      }
    }

    mainPort.send(RenderDoneMessage(cfg.renderId));
  } catch (e) {
    mainPort.send(RenderErrorMessage(cfg.renderId, e.toString()));
  }
}
