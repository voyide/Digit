import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class EngineConfig {
  final BigInt startN;
  final int bNum;
  final int renderR;
  final int renderC;
  final int logicalR;
  final int logicalC;
  final int modM;
  final int lhsRule;
  final int rhs1Rule;
  final int rhs2Rule;
  final int logicOp;
  final String postType;
  final int iterK;
  final int postGridR;
  final int postGridC;
  final int targetT;
  final int modMc;
  final int tupleK;
  final Uint32List palette;
  final double hueShift;
  final int renderId;

  const EngineConfig({
    required this.startN,
    required this.bNum,
    required this.renderR,
    required this.renderC,
    required this.logicalR,
    required this.logicalC,
    required this.modM,
    required this.lhsRule,
    required this.rhs1Rule,
    required this.rhs2Rule,
    required this.logicOp,
    required this.postType,
    required this.iterK,
    required this.postGridR,
    required this.postGridC,
    required this.targetT,
    required this.modMc,
    required this.tupleK,
    required this.palette,
    required this.hueShift,
    required this.renderId,
  });
}

class ExportConfig {
  final EngineConfig engine;
  final bool isGif;
  final int frames;
  final String animMode;
  final int animStart;
  final int animEnd;
  final int animPVal;

  const ExportConfig({
    required this.engine,
    required this.isGif,
    this.frames = 1,
    this.animMode = 'modeA',
    this.animStart = 0,
    this.animEnd = 0,
    this.animPVal = 0,
  });
}

class RenderChunkMessage {
  final int renderId;
  final int rowStart;
  final int rowCount;
  final int width;
  final double progress;
  final TransferableTypedData data;

  const RenderChunkMessage({
    required this.renderId,
    required this.rowStart,
    required this.rowCount,
    required this.width,
    required this.progress,
    required this.data,
  });
}

class RenderDoneMessage {
  final int renderId;
  const RenderDoneMessage(this.renderId);
}

class RenderErrorMessage {
  final int renderId;
  final String error;
  const RenderErrorMessage(this.renderId, this.error);
}

int safeBase(int b) => math.max(2, b);
int safeMod(int m) => math.max(1, m);
int safeTupleK(int k) => math.max(1, k);

int devicePreviewCap() {
  try {
    if (Platform.isAndroid) {
      return Platform.numberOfProcessors >= 8 ? 1536 : 1024;
    }
  } catch (_) {}
  return 1024;
}

Uint32List buildPaletteData(int modM, double hueShift) {
  final safeM = safeMod(modM);
  final out = Uint32List(safeM);
  out[0] = 0x000000;
  for (int i = 1; i < safeM; i++) {
    final hue = (hueShift + (i * 360.0 / safeM)) % 360.0;
    final c = HSLColor.fromAHSL(1.0, hue, 0.85, 0.55).toColor();
    out[i] = (c.red << 16) | (c.green << 8) | c.blue;
  }
  return out;
}

bool fitsFastInt(BigInt startN, int span) {
  if (startN.isNegative) return false;
  final end = startN + BigInt.from(span);
  return end.bitLength <= 60;
}

class _DigitCursor {
  final int b;
  final Int32List digits;
  int k = 1;

  _DigitCursor(this.b, [int maxDigits = 128]) : digits = Int32List(maxDigits);

  void setInt(int n) {
    if (n <= 0) {
      k = 1;
      digits[1] = 0;
      return;
    }

    int t = n;
    int len = 0;
    while (t > 0) {
      len++;
      t ~/= b;
    }
    k = len;

    t = n;
    for (int i = k; i >= 1; i--) {
      digits[i] = t % b;
      t ~/= b;
    }
  }

  int digitAt(int i) {
    if (i <= k) return digits[i];
    return digits[((i - 1) % k) + 1];
  }

  void increment() {
    if (k == 1 && digits[1] == 0) {
      digits[1] = 1;
      return;
    }

    int pos = k;
    while (pos >= 1 && digits[pos] == b - 1) {
      digits[pos] = 0;
      pos--;
    }

    if (pos >= 1) {
      digits[pos]++;
      return;
    }

    k++;
    digits[1] = 1;
    for (int i = 2; i <= k; i++) {
      digits[i] = 0;
    }
  }
}

class _FastSolverRuntime {
  final EngineConfig cfg;
  final int b;
  final int tupleK;
  final bool isGlobal14;

  late final int stateCount;
  late final Int32List initVec;
  late final Int32List offsets;
  late final Int32List succ;

  _FastSolverRuntime(this.cfg)
      : b = safeBase(cfg.bNum),
        tupleK = safeTupleK(cfg.tupleK),
        isGlobal14 = cfg.lhsRule == 14 {
    _build();
  }

  bool _accept(int val, int di, int dNext) {
    final c1 = _evaluateRHS(cfg.rhs1Rule, val, di, dNext, b);
    if (cfg.logicOp == 2) {
      return c1 || _evaluateRHS(cfg.rhs2Rule, val, di, dNext, b);
    }
    return c1;
  }

  void _build() {
    if (isGlobal14) {
      stateCount = 0;
      initVec = Int32List(0);
      offsets = Int32List(0);
      succ = Int32List(0);
      return;
    }

    if (cfg.lhsRule == 1 ||
        cfg.lhsRule == 10 ||
        cfg.lhsRule == 11 ||
        (cfg.lhsRule >= 15 && cfg.lhsRule <= 18)) {
      stateCount = b * b;
    } else {
      stateCount = b;
    }

    initVec = Int32List(stateCount);

    if (cfg.lhsRule == 1) {
      for (int x1 = 0; x1 < b; x1++) {
        initVec[x1 * b + x1] = 1;
      }
    } else {
      for (int i = 0; i < stateCount; i++) {
        initVec[i] = 1;
      }
    }

    final pairCount = b * b;
    final flat = <int>[];
    final tmpOffsets = Int32List(pairCount * stateCount + 1);
    int off = 0;

    for (int pair = 0; pair < pairCount; pair++) {
      final di = pair ~/ b;
      final dNext = pair % b;

      for (int state = 0; state < stateCount; state++) {
        tmpOffsets[off++] = flat.length;

        if (cfg.lhsRule == 1) {
          final x1 = state ~/ b;
          for (int xNext = 0; xNext < b; xNext++) {
            final val = (x1 - xNext).abs();
            if (_accept(val, di, dNext)) {
              flat.add(x1 * b + xNext);
            }
          }
        } else if (cfg.lhsRule == 7) {
          final acc = state;
          for (int xNext = 0; xNext < b; xNext++) {
            final val = (acc - xNext).abs();
            if (_accept(val, di, dNext)) {
              flat.add(val);
            }
          }
        } else if (cfg.lhsRule == 10 || cfg.lhsRule == 11) {
          final a = state ~/ b;
          final bVal = state % b;
          for (int c = 0; c < b; c++) {
            final val = cfg.lhsRule == 10
                ? (((a - bVal).abs() - (bVal - c).abs()).abs())
                : (a - bVal - c).abs();

            if (_accept(val, di, dNext)) {
              flat.add(bVal * b + c);
            }
          }
        } else if (cfg.lhsRule >= 15 && cfg.lhsRule <= 18) {
          final xiX = state % b;
          final xiY = state ~/ b;
          for (int nextState = 0; nextState < stateCount; nextState++) {
            final xNextX = nextState % b;
            final xNextY = nextState ~/ b;
            final dx = xiX - xNextX;
            final dy = xiY - xNextY;
            final dist = math.sqrt((dx * dx + dy * dy).toDouble());

            int val = 0;
            if (cfg.lhsRule == 15) val = dist.toInt();
            if (cfg.lhsRule == 16) val = dist.floor();
            if (cfg.lhsRule == 17) val = dist.ceil();
            if (cfg.lhsRule == 18) val = dist.round();

            if (_accept(val, di, dNext)) {
              flat.add(nextState);
            }
          }
        } else {
          final xi = state;
          for (int xNext = 0; xNext < b; xNext++) {
            final val = _evaluateLHS(cfg.lhsRule, xi, xNext, b, di, dNext);
            if (_accept(val, di, dNext)) {
              flat.add(xNext);
            }
          }
        }
      }
    }

    tmpOffsets[off] = flat.length;
    offsets = tmpOffsets;
    succ = Int32List.fromList(flat);
  }
}

class _FastSolverRunner {
  final _FastSolverRuntime rt;
  final _DigitCursor cursor;
  final Int32List _a;
  final Int32List _b;

  _FastSolverRunner(this.rt)
      : cursor = _DigitCursor(rt.b),
        _a = Int32List(math.max(1, rt.stateCount)),
        _b = Int32List(math.max(1, rt.stateCount));

  int solveModInt(int n, int mod) {
    cursor.setInt(n);
    return solveCurrentMod(mod);
  }

  int solveCurrentMod(int mod) {
    final safeM = safeMod(mod);
    if (safeM == 1) return 0;

    if (rt.isGlobal14) {
      return _solveGlobal14Mod(rt.cfg, cursor, safeM);
    }

    Int32List cur = _a;
    Int32List next = _b;

    for (int i = 0; i < rt.stateCount; i++) {
      cur[i] = rt.initVec[i];
    }

    final loopEnd = math.max(1, cursor.k + rt.tupleK - 1);

    for (int i = 1; i <= loopEnd; i++) {
      final pair = cursor.digitAt(i) * rt.b + cursor.digitAt(i + 1);
      next.fillRange(0, rt.stateCount, 0);

      final base = pair * rt.stateCount;
      for (int state = 0; state < rt.stateCount; state++) {
        final ways = cur[state];
        if (ways == 0) continue;

        final start = rt.offsets[base + state];
        final end = rt.offsets[base + state + 1];

        for (int p = start; p < end; p++) {
          final ns = rt.succ[p];
          int nv = next[ns] + ways;
          if (nv >= safeM) nv %= safeM;
          next[ns] = nv;
        }
      }

      final tmp = cur;
      cur = next;
      next = tmp;
    }

    int total = 0;
    for (int i = 0; i < rt.stateCount; i++) {
      total += cur[i];
      if (total >= safeM) total %= safeM;
    }
    return total % safeM;
  }
}

int _solveGlobal14Mod(EngineConfig cfg, _DigitCursor cursor, int mod) {
  final b = safeBase(cfg.bNum);
  final loopEnd = math.max(1, cursor.k + safeTupleK(cfg.tupleK) - 1);
  final L = loopEnd + 1;
  final maxSum = L * (b - 1);

  final dp = Int32List(maxSum + 1);
  final nextDp = Int32List(maxSum + 1);

  int totalWays = 0;

  for (int x1 = 0; x1 < b; x1++) {
    for (int sigma = x1; sigma <= maxSum; sigma++) {
      dp.fillRange(0, maxSum + 1, 0);
      dp[x1] = 1;

      bool possible = true;

      for (int i = 1; i <= loopEnd; i++) {
        final di = cursor.digitAt(i);
        final dNext = cursor.digitAt(i + 1);

        nextDp.fillRange(0, maxSum + 1, 0);
        bool hasState = false;

        for (int ci = x1; ci <= sigma; ci++) {
          final ways = dp[ci];
          if (ways == 0) continue;

          for (int xNext = 0; xNext < b; xNext++) {
            final pi = 2 * x1 - ci;
            final si = 2 * xNext + ci - sigma;
            final val = (pi.abs() - si.abs()).abs();

            bool c1 = _evaluateRHS(cfg.rhs1Rule, val, di, dNext, b);
            bool ok = c1;
            if (cfg.logicOp == 2) {
              ok = c1 || _evaluateRHS(cfg.rhs2Rule, val, di, dNext, b);
            }

            if (ok) {
              final nextC = ci + xNext;
              if (nextC <= sigma) {
                int nv = nextDp[nextC] + ways;
                if (nv >= mod) nv %= mod;
                nextDp[nextC] = nv;
                hasState = true;
              }
            }
          }
        }

        if (!hasState) {
          possible = false;
          break;
        }

        for (int z = 0; z <= maxSum; z++) {
          dp[z] = nextDp[z];
        }
      }

      if (possible) {
        totalWays += dp[sigma];
        if (totalWays >= mod) totalWays %= mod;
      }
    }
  }

  return totalWays % mod;
}

int _pixelModInt(int n, EngineConfig cfg, _FastSolverRunner runner) {
  final safeM = safeMod(cfg.modM);

  switch (cfg.postType) {
    case 'NONE':
      return runner.solveModInt(n, safeM);

    case 'ITERATE':
      final bigB = BigInt.from(safeBase(cfg.bNum));
      int result = _solveForN(BigInt.from(n), bigB, cfg);
      for (int i = 1; i < cfg.iterK; i++) {
        result = _solveForN(BigInt.from(result), bigB, cfg);
      }
      return result % safeM;

    case 'C_SEQ':
      final safeMc = safeMod(cfg.modMc);
      final blockSize = cfg.postGridR * cfg.postGridC;
      final block = n ~/ blockSize;
      final idx = n % blockSize;
      final subR = idx ~/ cfg.postGridC;
      final subC = idx % cfg.postGridC;
      final target = ((cfg.targetT % safeMc) + safeMc) % safeMc;

      int count = 0;
      for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
          if (dr == 0 && dc == 0) continue;
          final nr = subR + dr;
          final nc = subC + dc;
          if (nr >= 0 &&
              nr < cfg.postGridR &&
              nc >= 0 &&
              nc < cfg.postGridC) {
            final nPrime = block * blockSize + nr * cfg.postGridC + nc;
            if (runner.solveModInt(nPrime, safeMc) == target) {
              count++;
            }
          }
        }
      }
      return count % safeM;

    case 'D_SEQ':
      final blockSize = cfg.postGridR * cfg.postGridC;
      final baseN = n * blockSize;
      final minDim = math.min(cfg.postGridR, cfg.postGridC);
      int sum = 0;
      for (int i = 0; i < minDim; i++) {
        sum += runner.solveModInt(baseN + i * cfg.postGridC + i, safeM);
        if (sum >= safeM) sum %= safeM;
      }
      return sum % safeM;

    default:
      return runner.solveModInt(n, safeM);
  }
}

void liveRenderIsolate(List<dynamic> args) {
  final SendPort mainPort = args[0] as SendPort;
  final EngineConfig cfg = args[1] as EngineConfig;

  try {
    final palette = (cfg.palette.length == safeMod(cfg.modM))
        ? cfg.palette
        : buildPaletteData(cfg.modM, cfg.hueShift);

    final w = cfg.renderC;
    final h = cfg.renderR;

    final xMap = Int32List(w);
    final yMap = Int32List(h);

    for (int c = 0; c < w; c++) {
      xMap[c] = (c * cfg.logicalC) ~/ w;
    }
    for (int r = 0; r < h; r++) {
      yMap[r] = (r * cfg.logicalR) ~/ h;
    }

    final fastInt = fitsFastInt(cfg.startN, cfg.logicalR * cfg.logicalC);
    final runtime = _FastSolverRuntime(cfg);
    final runner = _FastSolverRunner(runtime);
    final rowsPerChunk = math.min(48, math.max(16, h ~/ 32));
    final bigB = BigInt.from(safeBase(cfg.bNum));

    for (int rowStart = 0; rowStart < h; rowStart += rowsPerChunk) {
      final rowCount = math.min(rowsPerChunk, h - rowStart);
      final bytes = Uint8List(rowCount * w * 4);
      int p = 0;

      for (int rr = 0; rr < rowCount; rr++) {
        final srcR = yMap[rowStart + rr];

        if (fastInt) {
          final baseRowIndex = srcR * cfg.logicalC;
          final startInt = cfg.startN.toInt();

          for (int c = 0; c < w; c++) {
            final n = startInt + baseRowIndex + xMap[c];
            final modVal = _pixelModInt(n, cfg, runner);
            final color = palette[modVal % palette.length];
            bytes[p++] = (color >> 16) & 0xFF;
            bytes[p++] = (color >> 8) & 0xFF;
            bytes[p++] = color & 0xFF;
            bytes[p++] = 255;
          }
        } else {
          for (int c = 0; c < w; c++) {
            final n = cfg.startN + BigInt.from(srcR * cfg.logicalC + xMap[c]);
            int result = 0;

            if (cfg.postType == 'NONE') {
              result = _solveForN(n, bigB, cfg);
            } else if (cfg.postType == 'ITERATE') {
              result = _solveForN(n, bigB, cfg);
              for (int i = 1; i < cfg.iterK; i++) {
                result = _solveForN(BigInt.from(result), bigB, cfg);
              }
            } else if (cfg.postType == 'C_SEQ') {
              final blockSize = BigInt.from(cfg.postGridR * cfg.postGridC);
              final block = n ~/ blockSize;
              final idx = n % blockSize;
              final subR = (idx ~/ BigInt.from(cfg.postGridC)).toInt();
              final subC = (idx % BigInt.from(cfg.postGridC)).toInt();

              int count = 0;
              for (int dr = -1; dr <= 1; dr++) {
                for (int dc = -1; dc <= 1; dc++) {
                  if (dr == 0 && dc == 0) continue;
                  final nr = subR + dr;
                  final nc = subC + dc;
                  if (nr >= 0 &&
                      nr < cfg.postGridR &&
                      nc >= 0 &&
                      nc < cfg.postGridC) {
                    final nPrime =
                        block * blockSize + BigInt.from(nr * cfg.postGridC + nc);
                    if (_solveForN(nPrime, bigB, cfg) % safeMod(cfg.modMc) ==
                        (cfg.targetT % safeMod(cfg.modMc))) {
                      count++;
                    }
                  }
                }
              }
              result = count;
            } else if (cfg.postType == 'D_SEQ') {
              final blockSize = BigInt.from(cfg.postGridR * cfg.postGridC);
              final baseN = n * blockSize;
              final minDim = math.min(cfg.postGridR, cfg.postGridC);
              int sum = 0;
              for (int i = 0; i < minDim; i++) {
                final nPrime = baseN + BigInt.from(i * cfg.postGridC + i);
                sum += _solveForN(nPrime, bigB, cfg);
              }
              result = sum;
            }

            final color = palette[result % palette.length];
            bytes[p++] = (color >> 16) & 0xFF;
            bytes[p++] = (color >> 8) & 0xFF;
            bytes[p++] = color & 0xFF;
            bytes[p++] = 255;
          }
        }
      }

      mainPort.send(
        RenderChunkMessage(
          renderId: cfg.renderId,
          rowStart: rowStart,
          rowCount: rowCount,
          width: w,
          progress: (rowStart + rowCount) / h,
          data: TransferableTypedData.fromList([bytes]),
        ),
      );
    }

    mainPort.send(RenderDoneMessage(cfg.renderId));
  } catch (e) {
    mainPort.send(RenderErrorMessage(cfg.renderId, e.toString()));
  }
}

Uint8List renderFullRgbaBytes(EngineConfig cfg) {
  final w = cfg.renderC;
  final h = cfg.renderR;
  final out = Uint8List(w * h * 4);

  final palette = (cfg.palette.length == safeMod(cfg.modM))
      ? cfg.palette
      : buildPaletteData(cfg.modM, cfg.hueShift);

  final fastInt = fitsFastInt(cfg.startN, w * h);
  final runtime = _FastSolverRuntime(cfg);
  final runner = _FastSolverRunner(runtime);
  final bigB = BigInt.from(safeBase(cfg.bNum));

  int p = 0;

  if (fastInt && cfg.postType == 'NONE') {
    final startInt = cfg.startN.toInt();
    runner.cursor.setInt(startInt);

    for (int r = 0; r < h; r++) {
      for (int c = 0; c < w; c++) {
        final modVal = runner.solveCurrentMod(safeMod(cfg.modM));
        final color = palette[modVal];
        out[p++] = (color >> 16) & 0xFF;
        out[p++] = (color >> 8) & 0xFF;
        out[p++] = color & 0xFF;
        out[p++] = 255;

        if (!(r == h - 1 && c == w - 1)) {
          runner.cursor.increment();
        }
      }
    }
    return out;
  }

  if (fastInt) {
    final startInt = cfg.startN.toInt();
    for (int r = 0; r < h; r++) {
      final rowBase = startInt + r * w;
      for (int c = 0; c < w; c++) {
        final modVal = _pixelModInt(rowBase + c, cfg, runner);
        final color = palette[modVal % palette.length];
        out[p++] = (color >> 16) & 0xFF;
        out[p++] = (color >> 8) & 0xFF;
        out[p++] = color & 0xFF;
        out[p++] = 255;
      }
    }
    return out;
  }

  for (int r = 0; r < h; r++) {
    for (int c = 0; c < w; c++) {
      final n = cfg.startN + BigInt.from(r * w + c);
      int result = 0;

      if (cfg.postType == 'NONE') {
        result = _solveForN(n, bigB, cfg);
      } else if (cfg.postType == 'ITERATE') {
        result = _solveForN(n, bigB, cfg);
        for (int i = 1; i < cfg.iterK; i++) {
          result = _solveForN(BigInt.from(result), bigB, cfg);
        }
      } else if (cfg.postType == 'C_SEQ') {
        final blockSize = BigInt.from(cfg.postGridR * cfg.postGridC);
        final block = n ~/ blockSize;
        final idx = n % blockSize;
        final subR = (idx ~/ BigInt.from(cfg.postGridC)).toInt();
        final subC = (idx % BigInt.from(cfg.postGridC)).toInt();
        int count = 0;

        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            final nr = subR + dr;
            final nc = subC + dc;
            if (nr >= 0 &&
                nr < cfg.postGridR &&
                nc >= 0 &&
                nc < cfg.postGridC) {
              final nPrime =
                  block * blockSize + BigInt.from(nr * cfg.postGridC + nc);
              if (_solveForN(nPrime, bigB, cfg) % safeMod(cfg.modMc) ==
                  (cfg.targetT % safeMod(cfg.modMc))) {
                count++;
              }
            }
          }
        }
        result = count;
      } else if (cfg.postType == 'D_SEQ') {
        final blockSize = BigInt.from(cfg.postGridR * cfg.postGridC);
        final baseN = n * blockSize;
        final minDim = math.min(cfg.postGridR, cfg.postGridC);
        int sum = 0;
        for (int i = 0; i < minDim; i++) {
          final nPrime = baseN + BigInt.from(i * cfg.postGridC + i);
          sum += _solveForN(nPrime, bigB, cfg);
        }
        result = sum;
      }

      final color = palette[result % palette.length];
      out[p++] = (color >> 16) & 0xFF;
      out[p++] = (color >> 8) & 0xFF;
      out[p++] = color & 0xFF;
      out[p++] = 255;
    }
  }

  return out;
}

Uint8List encodePngBytes(int width, int height, Uint8List rgba) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image, level: 1));
}

Future<Uint8List> backgroundExportTask(ExportConfig eCfg) async {
  if (!eCfg.isGif) {
    final rgba = renderFullRgbaBytes(eCfg.engine);
    return encodePngBytes(eCfg.engine.renderC, eCfg.engine.renderR, rgba);
  }

  img.Image? animation;

  for (int f = 0; f < eCfg.frames; f++) {
    int currentB = eCfg.engine.bNum;
    int currentM = eCfg.engine.modM;
    BigInt currentStart = eCfg.engine.startN;

    if (eCfg.animMode == 'modeA') {
      currentStart = BigInt.from(eCfg.animPVal * currentB + f) *
          BigInt.from(eCfg.engine.renderR * eCfg.engine.renderC);
    } else if (eCfg.animMode == 'modeB') {
      currentB = eCfg.animStart + f;
      currentStart = BigInt.from(eCfg.animPVal) *
          BigInt.from(eCfg.engine.renderR * eCfg.engine.renderC);
    } else if (eCfg.animMode == 'modeC') {
      currentM = eCfg.animStart + f;
      currentStart = BigInt.from(eCfg.animPVal) *
          BigInt.from(eCfg.engine.renderR * eCfg.engine.renderC);
    }

    final frameCfg = EngineConfig(
      startN: currentStart,
      bNum: currentB,
      renderR: eCfg.engine.renderR,
      renderC: eCfg.engine.renderC,
      logicalR: eCfg.engine.renderR,
      logicalC: eCfg.engine.renderC,
      modM: currentM,
      lhsRule: eCfg.engine.lhsRule,
      rhs1Rule: eCfg.engine.rhs1Rule,
      rhs2Rule: eCfg.engine.rhs2Rule,
      logicOp: eCfg.engine.logicOp,
      postType: eCfg.engine.postType,
      iterK: eCfg.engine.iterK,
      postGridR: eCfg.engine.postGridR,
      postGridC: eCfg.engine.postGridC,
      targetT: eCfg.engine.targetT,
      modMc: eCfg.engine.modMc,
      tupleK: eCfg.engine.tupleK,
      palette: buildPaletteData(currentM, eCfg.engine.hueShift),
      hueShift: eCfg.engine.hueShift,
      renderId: 0,
    );

    final rgba = renderFullRgbaBytes(frameCfg);
    final frame = img.Image.fromBytes(
      width: frameCfg.renderC,
      height: frameCfg.renderR,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    if (animation == null) {
      animation = frame;
    } else {
      animation.addFrame(frame);
    }
  }

  return Uint8List.fromList(img.encodeGif(animation!));
}

int _solveForN(BigInt n, BigInt bigB, EngineConfig config) {
  int b = config.bNum;
  int k = 0;

  if (n == BigInt.zero) {
    k = 1;
  } else {
    BigInt t = n;
    while (t > BigInt.zero) {
      k++;
      t = t ~/ bigB;
    }
  }

  int loopEnd = k + (config.tupleK > 0 ? config.tupleK - 1 : 0);
  if (loopEnd < 1) loopEnd = 1;

  List<int> d = List.filled(loopEnd + 3, 0);
  BigInt temp = n;
  if (n != BigInt.zero) {
    int idx = k;
    while (temp > BigInt.zero && idx > 0) {
      d[idx] = (temp % bigB).toInt();
      temp = temp ~/ bigB;
      idx--;
    }
  }
  d[0] = d[k];
  for (int w = k + 1; w < d.length; w++) {
    d[w] = d[(w - 1) % k + 1];
  }

  int totalWays = 0;
  int lhs = config.lhsRule;

  if (lhs == 14) {
    int L = loopEnd + 1;
    int maxSum = L * (b - 1);
    List<int> dp = List.filled(maxSum + 1, 0);
    List<int> nextDp = List.filled(maxSum + 1, 0);

    for (int x1 = 0; x1 < b; x1++) {
      for (int Sigma = x1; Sigma <= maxSum; Sigma++) {
        dp.fillRange(0, maxSum + 1, 0);
        dp[x1] = 1;
        bool possible = true;

        for (int i = 1; i <= loopEnd; i++) {
          int di = d[i], dNext = d[i + 1];
          nextDp.fillRange(0, maxSum + 1, 0);
          bool hasState = false;

          for (int Ci = x1; Ci <= Sigma; Ci++) {
            if (dp[Ci] == 0) continue;
            for (int xNext = 0; xNext < b; xNext++) {
              int Pi = 2 * x1 - Ci;
              int Si = 2 * xNext + Ci - Sigma;
              int val = (Pi.abs() - Si.abs()).abs();

              bool c1 = _evaluateRHS(config.rhs1Rule, val, di, dNext, b);
              bool conditionMet = c1;
              if (config.logicOp == 2) {
                conditionMet =
                    c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
              }

              if (conditionMet) {
                int nextC = Ci + xNext;
                if (nextC <= Sigma) {
                  nextDp[nextC] += dp[Ci];
                  hasState = true;
                }
              }
            }
          }
          if (!hasState) {
            possible = false;
            break;
          }
          List<int> tArr = dp;
          dp = nextDp;
          nextDp = tArr;
        }
        if (possible) totalWays += dp[Sigma];
      }
    }
    return totalWays;
  }

  if (lhs >= 15 && lhs <= 18) {
    int numStates = b * b;
    List<int> v = List.filled(numStates, 1);
    List<int> nextV = List.filled(numStates, 0);

    for (int i = 1; i <= loopEnd; i++) {
      int di = d[i], dNext = d[i + 1];
      nextV.fillRange(0, numStates, 0);

      for (int state = 0; state < numStates; state++) {
        if (v[state] == 0) continue;
        int xiX = state % b, xiY = state ~/ b;

        for (int nextState = 0; nextState < numStates; nextState++) {
          int xNextX = nextState % b, xNextY = nextState ~/ b;
          double dist =
              math.sqrt(math.pow(xiX - xNextX, 2) + math.pow(xiY - xNextY, 2));
          int val = 0;

          if (lhs == 15) {
            val = dist.toInt();
          } else if (lhs == 16) {
            val = dist.floor();
          } else if (lhs == 17) {
            val = dist.ceil();
          } else if (lhs == 18) {
            val = dist.round();
          }

          bool c1 = _evaluateRHS(config.rhs1Rule, val, di, dNext, b);
          bool conditionMet = c1;
          if (config.logicOp == 2) {
            conditionMet =
                c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
          }

          if (conditionMet) nextV[nextState] += v[state];
        }
      }
      List<int> tArr = v;
      v = nextV;
      nextV = tArr;
    }
    for (int i = 0; i < numStates; i++) {
      totalWays += v[i];
    }
    return totalWays;
  }

  if (lhs == 7) {
    List<int> v = List.filled(b, 1);
    List<int> nextV = List.filled(b, 0);

    for (int i = 1; i <= loopEnd; i++) {
      int di = d[i], dNext = d[i + 1];
      nextV.fillRange(0, b, 0);

      for (int acc = 0; acc < b; acc++) {
        if (v[acc] == 0) continue;
        for (int xNext = 0; xNext < b; xNext++) {
          int val = (acc - xNext).abs();

          bool c1 = _evaluateRHS(config.rhs1Rule, val, di, dNext, b);
          bool conditionMet = c1;
          if (config.logicOp == 2) {
            conditionMet =
                c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
          }

          if (conditionMet) nextV[val] += v[acc];
        }
      }
      List<int> tArr = v;
      v = nextV;
      nextV = tArr;
    }
    for (int i = 0; i < b; i++) {
      totalWays += v[i];
    }
    return totalWays;
  }

  if (lhs == 10 || lhs == 11) {
    int numStates = b * b;
    List<int> v = List.filled(numStates, 1);
    List<int> nextV = List.filled(numStates, 0);

    for (int i = 1; i <= loopEnd; i++) {
      int di = d[i], dNext = d[i + 1];
      nextV.fillRange(0, numStates, 0);

      for (int a = 0; a < b; a++) {
        for (int bVal = 0; bVal < b; bVal++) {
          if (v[a * b + bVal] == 0) continue;

          for (int c = 0; c < b; c++) {
            int val = 0;
            if (lhs == 10) {
              val = ((a - bVal).abs() - (bVal - c).abs()).abs();
            } else if (lhs == 11) {
              val = (a - bVal - c).abs();
            }

            bool c1 = _evaluateRHS(config.rhs1Rule, val, di, dNext, b);
            bool conditionMet = c1;
            if (config.logicOp == 2) {
              conditionMet =
                  c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
            }

            if (conditionMet) nextV[bVal * b + c] += v[a * b + bVal];
          }
        }
      }
      List<int> tArr = v;
      v = nextV;
      nextV = tArr;
    }
    for (int i = 0; i < numStates; i++) {
      totalWays += v[i];
    }
    return totalWays;
  }

  List<int> v = List.filled(b, 1);
  List<int> nextV = List.filled(b, 0);
  bool needsX1 = (lhs == 1);

  if (needsX1) {
    for (int x1 = 0; x1 < b; x1++) {
      v.fillRange(0, b, 0);
      v[x1] = 1;

      for (int i = 1; i <= loopEnd; i++) {
        int di = d[i], dNext = d[i + 1];
        nextV.fillRange(0, b, 0);

        for (int xi = 0; xi < b; xi++) {
          if (v[xi] == 0) continue;
          for (int xNext = 0; xNext < b; xNext++) {
            int val = (x1 - xNext).abs();

            bool c1 = _evaluateRHS(config.rhs1Rule, val, di, dNext, b);
            bool conditionMet = c1;
            if (config.logicOp == 2) {
              conditionMet =
                  c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
            }

            if (conditionMet) nextV[xNext] += v[xi];
          }
        }
        List<int> tArr = v;
        v = nextV;
        nextV = tArr;
      }
      for (int i = 0; i < b; i++) {
        totalWays += v[i];
      }
    }
    return totalWays;
  }

  for (int i = 1; i <= loopEnd; i++) {
    int di = d[i], dNext = d[i + 1];
    nextV.fillRange(0, b, 0);

    for (int xi = 0; xi < b; xi++) {
      if (v[xi] == 0) continue;
      for (int xNext = 0; xNext < b; xNext++) {
        int val = _evaluateLHS(config.lhsRule, xi, xNext, b, di, dNext);
        bool c1 = _evaluateRHS(config.rhs1Rule, val, di, dNext, b);

        bool conditionMet = c1;
        if (config.logicOp == 2) {
          conditionMet =
              c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
        }

        if (conditionMet) nextV[xNext] += v[xi];
      }
    }
    List<int> tArr = v;
    v = nextV;
    nextV = tArr;
  }

  for (int i = 0; i < b; i++) {
    totalWays += v[i];
  }
  return totalWays;
}

int _evaluateLHS(int rule, int xi, int xNext, int b, int di, int dNext) {
  switch (rule) {
    case 0:
      return (xi - xNext).abs();
    case 2:
      return (xNext - xi + b) % b;
    case 3:
      return (xi + xNext) % b;
    case 4:
      return xi > xNext ? xi : xNext;
    case 5:
      return xi < xNext ? xi : xNext;
    case 6:
      return (xi ^ xNext) % b;
    case 8:
      return (xi * xNext) % b;
    case 9:
      return ((b - 1 - xi) - xNext).abs();
    case 12:
      return ((xi * xi) % b - xNext).abs();
    case 19:
      return ((xi * xi * xi) + (xNext * xNext * xNext)) % b;
    case 20:
      return ((xi * xi) - (xNext * xNext)).abs();
    case 21:
      int a = xi, c = xNext;
      while (c != 0) {
        int t = c;
        c = a % c;
        a = t;
      }
      return a;
    case 22:
      int a2 = xi, c2 = xNext;
      int gcd = 1;
      while (c2 != 0) {
        int t = c2;
        c2 = a2 % c2;
        a2 = t;
      }
      gcd = a2;
      return gcd == 0 ? 0 : ((xi * xNext) ~/ gcd) % b;
    case 23:
      return (xi - (b ~/ 2)).abs() + (xNext - (b ~/ 2)).abs();
    case 24:
      return (xi | xNext) % b;
    case 25:
      return (xi & xNext) % b;
    case 26:
      return ((xi << 1) ^ xNext) % b;
    case 27:
      return ((xi * (xi + 1)) ~/ 2) % b;
    case 28:
      return ((xi * xi) + (xi * xNext) + (xNext * xNext)) % b;
    case 29:
      return ((xi * di) + (xNext * dNext)) % b;
    case 30:
      return ((xi + 1) * (xNext + 1)) % b;
    default:
      return (xi - xNext).abs();
  }
}

bool _evaluateRHS(int rule, int val, int di, int dNext, int b) {
  switch (rule) {
    case 0:
      return val == di;
    case 1:
      return val == (b - 1 - di);
    case 2:
      return val <= di;
    case 3:
      return val >= di;
    case 4:
      return val != di;
    case 5:
      return (val % 2) == (di % 2);
    case 6:
      return val == (b ~/ 2);
    case 7:
      return val < di;
    case 8:
      return val > di;
    case 9:
      return val == (di + 1) % b;
    case 10:
      return val == (di + dNext) % b;
    case 11:
      return val == (di * dNext) % b;
    case 12:
      return (val % 3) == (di % 3);
    case 13:
      return (val % 4) == (di % 4);
    case 14:
      return val == ((di * di) % b);
    case 15:
      return val == (di - dNext).abs();
    case 16:
      return val == (di > dNext ? di : dNext);
    case 17:
      return val == (di < dNext ? di : dNext);
    case 18:
      return val == (di ^ dNext);
    case 19:
      return val > (b ~/ 2);
    case 20:
      return val < (b ~/ 2);
    case 21:
      return val == (b - di) % b;
    case 22:
      return val != (di + 1) % b;
    case 23:
      return val <= (di + (b ~/ 2)) % b;
    case 24:
      return val >= (di - (b ~/ 2)) % b;
    default:
      return val == di;
  }
}
