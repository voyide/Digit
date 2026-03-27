import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const UniversalSequencerApp());
}

class UniversalSequencerApp extends StatelessWidget {
  const UniversalSequencerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Tuple Sequence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF8A65),
          secondary: Color(0xFF7C4DFF),
        ),
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.zero),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Color(0xFFFF8A65), width: 2),
          ),
          filled: true,
          fillColor: Color(0xFF1E1E1E),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: GoogleFonts.spaceMono(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      home: const SequencerWorkspace(),
    );
  }
}

// ---------------- CORE DATA ----------------

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

  EngineConfig({
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

  ExportConfig({
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

  RenderChunkMessage({
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

class StripeJob {
  final EngineConfig cfg;
  final int rowStart;
  final int rowEnd;
  StripeJob(this.cfg, this.rowStart, this.rowEnd);
}

class StripeResult {
  final int rowStart;
  final int rowCount;
  final TransferableTypedData data;
  StripeResult(this.rowStart, this.rowCount, this.data);
}

// ---------------- HELPERS ----------------

int _safeBase(int b) => math.max(2, b);
int _safeMod(int m) => math.max(1, m);
int _safeTupleK(int k) => math.max(1, k);

int _devicePreviewCap() {
  try {
    if (Platform.isAndroid) {
      return Platform.numberOfProcessors >= 8 ? 1536 : 1024;
    }
  } catch (_) {}
  return 1024;
}

Uint32List _buildPaletteData(int modM, double hueShift) {
  final safeM = _safeMod(modM);
  final out = Uint32List(safeM);
  out[0] = 0x000000;
  for (int i = 1; i < safeM; i++) {
    final hue = (hueShift + (i * 360.0 / safeM)) % 360.0;
    final c = HSLColor.fromAHSL(1.0, hue, 0.85, 0.55).toColor();
    out[i] = (c.red << 16) | (c.green << 8) | c.blue;
  }
  return out;
}

bool _fitsFastInt(BigInt startN, int span) {
  if (startN.isNegative) return false;
  final end = startN + BigInt.from(span);
  return end.bitLength <= 60;
}

// ---------------- FAST DIGIT CURSOR ----------------

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

// ---------------- FAST PRECOMPUTED RUNTIME ----------------

class _FastSolverRuntime {
  final EngineConfig cfg;
  final int b;
  final int tupleK;
  final bool isGlobal14;

  late final int stateCount;
  late final Int32List initVec;
  late final Int32List offsets;
  late final Uint16List succ;

  _FastSolverRuntime(this.cfg)
      : b = _safeBase(cfg.bNum),
        tupleK = _safeTupleK(cfg.tupleK),
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
      succ = Uint16List(0);
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
    succ = Uint16List.fromList(flat);
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
    final safeMod = _safeMod(mod);
    if (safeMod == 1) return 0;

    if (rt.isGlobal14) {
      return _solveGlobal14Mod(rt.cfg, cursor, safeMod);
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
          if (nv >= safeMod) nv %= safeMod;
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
      if (total >= safeMod) total %= safeMod;
    }
    return total % safeMod;
  }
}

int _solveGlobal14Mod(EngineConfig cfg, _DigitCursor cursor, int mod) {
  final b = _safeBase(cfg.bNum);
  final loopEnd = math.max(1, cursor.k + _safeTupleK(cfg.tupleK) - 1);
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
  final safeModM = _safeMod(cfg.modM);

  switch (cfg.postType) {
    case 'NONE':
      return runner.solveModInt(n, safeModM);

    case 'ITERATE':
      final bigB = BigInt.from(_safeBase(cfg.bNum));
      int result = _solveForN(BigInt.from(n), bigB, cfg);
      for (int i = 1; i < cfg.iterK; i++) {
        result = _solveForN(BigInt.from(result), bigB, cfg);
      }
      return result % safeModM;

    case 'C_SEQ':
      final safeMc = _safeMod(cfg.modMc);
      final blockSize = cfg.postGridR * cfg.postGridC;
      final block = n ~/ blockSize;
      final idx = n % blockSize;
      final subR = idx ~/ cfg.postGridC;
      final subC = idx % cfg.postGridC;

      int count = 0;
      final target = ((cfg.targetT % safeMc) + safeMc) % safeMc;

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
      return count % safeModM;

    case 'D_SEQ':
      final blockSize = cfg.postGridR * cfg.postGridC;
      final baseN = n * blockSize;
      final minDim = math.min(cfg.postGridR, cfg.postGridC);
      int sum = 0;
      for (int i = 0; i < minDim; i++) {
        sum += runner.solveModInt(baseN + i * cfg.postGridC + i, safeModM);
        if (sum >= safeModM) sum %= safeModM;
      }
      return sum % safeModM;

    default:
      return runner.solveModInt(n, safeModM);
  }
}

// ---------------- LIVE PREVIEW ISOLATE ----------------

void _liveRenderIsolate(List<dynamic> args) {
  final SendPort mainPort = args[0] as SendPort;
  final EngineConfig cfg = args[1] as EngineConfig;

  try {
    final palette = (cfg.palette.length == _safeMod(cfg.modM))
        ? cfg.palette
        : _buildPaletteData(cfg.modM, cfg.hueShift);

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

    final fastInt = _fitsFastInt(cfg.startN, cfg.logicalR * cfg.logicalC);
    final runtime = _FastSolverRuntime(cfg);
    final runner = _FastSolverRunner(runtime);
    final rowsPerChunk = math.min(48, math.max(16, h ~/ 32));
    final bigB = BigInt.from(_safeBase(cfg.bNum));

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
                    if (_solveForN(nPrime, bigB, cfg) % _safeMod(cfg.modMc) ==
                        (cfg.targetT % _safeMod(cfg.modMc))) {
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

// ---------------- FULL FRAME RENDER / EXPORT ----------------

Uint8List _renderFullRgbaBytes(EngineConfig cfg) {
  final w = cfg.renderC;
  final h = cfg.renderR;
  final out = Uint8List(w * h * 4);

  final palette = (cfg.palette.length == _safeMod(cfg.modM))
      ? cfg.palette
      : _buildPaletteData(cfg.modM, cfg.hueShift);

  final fastInt = _fitsFastInt(cfg.startN, w * h);
  final runtime = _FastSolverRuntime(cfg);
  final runner = _FastSolverRunner(runtime);
  final bigB = BigInt.from(_safeBase(cfg.bNum));

  int p = 0;

  if (fastInt && cfg.postType == 'NONE') {
    final startInt = cfg.startN.toInt();
    runner.cursor.setInt(startInt);

    for (int r = 0; r < h; r++) {
      for (int c = 0; c < w; c++) {
        final modVal = runner.solveCurrentMod(_safeMod(cfg.modM));
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
              if (_solveForN(nPrime, bigB, cfg) % _safeMod(cfg.modMc) ==
                  (cfg.targetT % _safeMod(cfg.modMc))) {
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

StripeResult _renderStripe(StripeJob job) {
  final cfg = job.cfg;
  final w = cfg.renderC;
  final rows = job.rowEnd - job.rowStart;
  final out = Uint8List(rows * w * 4);

  final palette = (cfg.palette.length == _safeMod(cfg.modM))
      ? cfg.palette
      : _buildPaletteData(cfg.modM, cfg.hueShift);

  final fastInt = _fitsFastInt(
    cfg.startN + BigInt.from(job.rowStart * w),
    rows * w,
  );
  final runtime = _FastSolverRuntime(cfg);
  final runner = _FastSolverRunner(runtime);
  final bigB = BigInt.from(_safeBase(cfg.bNum));

  int p = 0;

  if (fastInt && cfg.postType == 'NONE') {
    final startInt = cfg.startN.toInt() + job.rowStart * w;
    runner.cursor.setInt(startInt);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < w; c++) {
        final modVal = runner.solveCurrentMod(_safeMod(cfg.modM));
        final color = palette[modVal];
        out[p++] = (color >> 16) & 0xFF;
        out[p++] = (color >> 8) & 0xFF;
        out[p++] = color & 0xFF;
        out[p++] = 255;

        if (!(r == rows - 1 && c == w - 1)) {
          runner.cursor.increment();
        }
      }
    }

    return StripeResult(
      job.rowStart,
      rows,
      TransferableTypedData.fromList([out]),
    );
  }

  if (fastInt) {
    final startInt = cfg.startN.toInt();
    for (int r = job.rowStart; r < job.rowEnd; r++) {
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

    return StripeResult(
      job.rowStart,
      rows,
      TransferableTypedData.fromList([out]),
    );
  }

  for (int r = job.rowStart; r < job.rowEnd; r++) {
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
              if (_solveForN(nPrime, bigB, cfg) % _safeMod(cfg.modMc) ==
                  (cfg.targetT % _safeMod(cfg.modMc))) {
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

  return StripeResult(
    job.rowStart,
    rows,
    TransferableTypedData.fromList([out]),
  );
}

Uint8List _encodePngBytes(int width, int height, Uint8List rgba) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image, level: 1));
}

Future<Uint8List> _backgroundExportTask(ExportConfig eCfg) async {
  if (!eCfg.isGif) {
    final rgba = _renderFullRgbaBytes(eCfg.engine);
    return _encodePngBytes(eCfg.engine.renderC, eCfg.engine.renderR, rgba);
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
      palette: _buildPaletteData(currentM, eCfg.engine.hueShift),
      hueShift: eCfg.engine.hueShift,
      renderId: 0,
    );

    final rgba = _renderFullRgbaBytes(frameCfg);
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

// ---------------- ORIGINAL ENGINE ----------------

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

// ---------------- UI ----------------

class SequencerWorkspace extends StatefulWidget {
  const SequencerWorkspace({super.key});

  @override
  State<SequencerWorkspace> createState() => _SequencerWorkspaceState();
}

class _SequencerWorkspaceState extends State<SequencerWorkspace> {
  ui.Image? _renderedGrid;
  double _renderProgress = 0.0;
  bool _isProcessing = false;

  Isolate? _renderIsolate;
  ReceivePort? _renderReceivePort;

  Timer? _debounceTimer;
  Uint8List? _previewPixels;
  int _previewW = 0;
  int _previewH = 0;
  int _activeRenderId = 0;
  bool _decodeScheduled = false;

  int _bNum = 3;
  int _modM = 4;
  int _pVal = 0;
  int _lhsRule = 0;
  int _rhs1Rule = 0;
  int _rhs2Rule = 1;
  int _logicOp = 0;
  int _tupleK = 1;

  int _viewScaleIdx = 2;
  int _customViewDim = 100;

  String _postType = 'NONE';
  int _iterK = 2;
  int _postGridScaleIdx = 1;
  int _customPostR = 10;
  int _customPostC = 10;
  int _targetT = 0;
  int _modMc = 4;

  String _animMode = 'modeA';
  int _animStart = 2;
  int _animEnd = 6;
  int _animPVal = 0;

  double _hueShift = 0.0;
  late Uint32List _currentPalette;

  final List<String> _lhsLabels = [
    "| xi - x(i+1) |",
    "Anchor | x1 - x(i+1) |",
    "(x(i+1) - xi + b) % b",
    "(xi + x(i+1)) % b",
    "max(xi, x(i+1))",
    "min(xi, x(i+1))",
    "xi ⊕ x(i+1)",
    "Accumulator Drop",
    "(xi × x(i+1)) % b",
    "|(b - 1 - xi) - x(i+1)|",
    "Lookback |xi-1 - xi|",
    "Lookahead |xi - x(i+2)|",
    "|(xi)² % b - x(i+1)|",
    "[OMITTED]",
    "Global Structure",
    "Complex Z Exact",
    "Complex Z Floor",
    "Complex Z Ceil",
    "Complex Z Round",
    "Sum of Cubes",
    "Diff of Squares",
    "GCD",
    "LCM",
    "Center Dist",
    "Bitwise OR",
    "Bitwise AND",
    "L-Shift XOR",
    "Triangular Num",
    "Quadratic Form",
    "D-weighted sum",
    "Shifted Product"
  ];

  final List<String> _rhsLabels = [
    "= di",
    "= b - 1 - di",
    "≤ di",
    "≥ di",
    "≠ di",
    "≡ di (mod 2)",
    "= floor(b/2)",
    "< di",
    "> di",
    "= (di + 1) % b",
    "= (di + d(i+1)) % b",
    "= (di × d(i+1)) % b",
    "≡ di (mod 3)",
    "≡ di (mod 4)",
    "= (di)² % b",
    "= |di - d(i+1)|",
    "= max(di, d(i+1))",
    "= min(di, d(i+1))",
    "= di ⊕ d(i+1)",
    "> floor(b/2)",
    "< floor(b/2)",
    "= (b - di) % b",
    "≠ (di + 1) % b",
    "≤ (di + b/2) % b",
    "≥ (di - b/2) % b"
  ];

  @override
  void initState() {
    super.initState();
    _generatePalette();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerRender();
    });
  }

  void _generatePalette() {
    _currentPalette = _buildPaletteData(_safeMod(_modM), _hueShift);
  }

  void _randomizeColors() {
    _hueShift = math.Random().nextDouble() * 360.0;
    _generatePalette();
    _debouncedRender();
  }

  int _getDim(int scaleIdx, int customDim) {
    final safeB = _safeBase(_bNum);
    if (scaleIdx == 4) return math.max(1, customDim);
    return math.pow(safeB, scaleIdx).toInt();
  }

  int _getPreviewDim(int logicalDim) => math.min(logicalDim, _devicePreviewCap());

  void _debouncedRender() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), _triggerRender);
  }

  void _schedulePreviewDecode({bool immediate = false}) {
    if (_previewPixels == null || _previewW <= 0 || _previewH <= 0) return;

    if (immediate) {
      _decodePreview();
      return;
    }

    if (_decodeScheduled) return;
    _decodeScheduled = true;

    Timer(const Duration(milliseconds: 80), () {
      _decodeScheduled = false;
      if (mounted) _decodePreview();
    });
  }

  void _decodePreview() {
    if (_previewPixels == null || _previewW <= 0 || _previewH <= 0) return;
    final copy = Uint8List.fromList(_previewPixels!);

    ui.decodeImageFromPixels(
      copy,
      _previewW,
      _previewH,
      ui.PixelFormat.rgba8888,
      (img) {
        if (!mounted) return;
        setState(() {
          _renderedGrid = img;
        });
      },
    );
  }

  Future<void> _triggerRender() async {
    final safeB = _safeBase(_bNum);
    final safeM = _safeMod(_modM);

    final logicalDim = _getDim(_viewScaleIdx, _customViewDim);
    final previewDim = _getPreviewDim(logicalDim);

    final postR = _getDim(_postGridScaleIdx, _customPostR);
    final postC = _getDim(_postGridScaleIdx, _customPostC);

    final renderId = ++_activeRenderId;

    final cfg = EngineConfig(
      startN: BigInt.from(_pVal * logicalDim * logicalDim),
      bNum: safeB,
      renderR: previewDim,
      renderC: previewDim,
      logicalR: logicalDim,
      logicalC: logicalDim,
      modM: safeM,
      lhsRule: _lhsRule,
      rhs1Rule: _rhs1Rule,
      rhs2Rule: _rhs2Rule,
      logicOp: _logicOp,
      postType: _postType,
      iterK: math.max(1, _iterK),
      postGridR: math.max(1, postR),
      postGridC: math.max(1, postC),
      targetT: _targetT,
      modMc: _safeMod(_modMc),
      tupleK: _safeTupleK(_tupleK),
      palette: _currentPalette,
      hueShift: _hueShift,
      renderId: renderId,
    );

    _renderReceivePort?.close();
    _renderIsolate?.kill(priority: Isolate.immediate);

    _previewPixels = Uint8List(previewDim * previewDim * 4);
    _previewW = previewDim;
    _previewH = previewDim;

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _renderProgress = 0.0;
      });
    }

    final rp = ReceivePort();
    _renderReceivePort = rp;

    rp.listen((message) {
      if (!mounted) return;

      if (message is RenderChunkMessage) {
        if (message.renderId != _activeRenderId) return;

        final bytes = message.data.materialize().asUint8List();
        final offset = message.rowStart * message.width * 4;
        _previewPixels!.setRange(offset, offset + bytes.length, bytes);

        setState(() {
          _renderProgress = message.progress;
        });

        _schedulePreviewDecode(immediate: message.progress >= 1.0);
      } else if (message is RenderDoneMessage) {
        if (message.renderId != _activeRenderId) return;
        setState(() {
          _isProcessing = false;
          _renderProgress = 1.0;
        });
        _schedulePreviewDecode(immediate: true);
      } else if (message is RenderErrorMessage) {
        if (message.renderId != _activeRenderId) return;
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Render failed: ${message.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    _renderIsolate = await Isolate.spawn(_liveRenderIsolate, [rp.sendPort, cfg]);
  }

  Future<void> _exportArtifact(bool asGif) async {
    setState(() {
      _isProcessing = true;
      _renderProgress = 0.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Processing export...'),
        backgroundColor: Color(0xFF7C4DFF),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final safeB = _safeBase(_bNum);
      final safeM = _safeMod(_modM);

      final dim = _getDim(_viewScaleIdx, _customViewDim);
      final postR = _getDim(_postGridScaleIdx, _customPostR);
      final postC = _getDim(_postGridScaleIdx, _customPostC);

      final baseCfg = EngineConfig(
        startN: BigInt.from(_pVal * dim * dim),
        bNum: safeB,
        renderR: dim,
        renderC: dim,
        logicalR: dim,
        logicalC: dim,
        modM: safeM,
        lhsRule: _lhsRule,
        rhs1Rule: _rhs1Rule,
        rhs2Rule: _rhs2Rule,
        logicOp: _logicOp,
        postType: _postType,
        iterK: math.max(1, _iterK),
        postGridR: math.max(1, postR),
        postGridC: math.max(1, postC),
        targetT: _targetT,
        modMc: _safeMod(_modMc),
        tupleK: _safeTupleK(_tupleK),
        palette: _currentPalette,
        hueShift: _hueShift,
        renderId: 0,
      );

      Uint8List resultBytes;

      if (!asGif) {
        final w = baseCfg.renderC;
        final h = baseCfg.renderR;
        final rgba = Uint8List(w * h * 4);

        int workers = math.min(4, math.max(1, Platform.numberOfProcessors - 1));
        final totalPixels = w * h;
        if (totalPixels >= 24000000) {
          workers = math.min(workers, 2);
        }
        if (totalPixels >= 50000000) {
          workers = 1;
        }

        final stripeH = (h / workers).ceil();
        int doneRows = 0;

        final futures = <Future<void>>[];
        for (int row = 0; row < h; row += stripeH) {
          final end = math.min(h, row + stripeH);
          futures.add(
            Isolate.run(() => _renderStripe(StripeJob(baseCfg, row, end))).then((res) {
              final bytes = res.data.materialize().asUint8List();
              final offset = res.rowStart * w * 4;
              rgba.setRange(offset, offset + bytes.length, bytes);

              doneRows += res.rowCount;
              if (mounted) {
                setState(() {
                  _renderProgress = doneRows / h;
                });
              }
            }),
          );
        }

        await Future.wait(futures);
        resultBytes = await Isolate.run(() => _encodePngBytes(w, h, rgba));
      } else {
        int frames = 1;
        if (_animMode == 'modeA') {
          frames = safeB;
        } else if (_animMode == 'modeB' || _animMode == 'modeC') {
          frames = math.max(1, (_animEnd - _animStart) + 1);
        }

        final eCfg = ExportConfig(
          engine: baseCfg,
          isGif: true,
          frames: frames,
          animMode: _animMode,
          animStart: _animStart,
          animEnd: _animEnd,
          animPVal: _animPVal,
        );

        resultBytes = await Isolate.run(() => _backgroundExportTask(eCfg));
      }

      final ext = asGif ? 'gif' : 'png';
      final tempDir = await getTemporaryDirectory();
      final file = await File(
        '${tempDir.path}/SEQ_b${safeB}_m${safeM}_${dim}x$dim.$ext',
      ).create();

      await file.writeAsBytes(resultBytes);

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _renderProgress = 1.0;
        });
      }

      await Share.shareXFiles(
        [XFile(file.path, mimeType: asGif ? 'image/gif' : 'image/png')],
        text: 'Universal Sequence Render',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _renderReceivePort?.close();
    _renderIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logicalDim = _getDim(_viewScaleIdx, _customViewDim);
    final previewDim = _getPreviewDim(logicalDim);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  if (_renderedGrid != null)
                    RawImage(
                      image: _renderedGrid,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                    ),
                  if (_isProcessing)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: _renderProgress,
                        backgroundColor: Colors.transparent,
                        color: Theme.of(context).colorScheme.primary,
                        minHeight: 4,
                      ),
                    ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.black87,
                      child: Text(
                        'b:${_safeBase(_bNum)} | m:${_safeMod(_modM)} | grid:$logicalDim | preview:$previewDim',
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ),
                  )
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumInput('BASE', _bNum, (v) {
                            _bNum = v;
                            _debouncedRender();
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildNumInput('MOD', _modM, (v) {
                            _modM = v;
                            _generatePalette();
                            _debouncedRender();
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildNumInput('RANGE', _pVal, (v) {
                            _pVal = v;
                            _debouncedRender();
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDropdown(
                            'GRID',
                            _viewScaleIdx - 1,
                            3,
                            (v) {
                              setState(() => _viewScaleIdx = v! + 1);
                              _debouncedRender();
                            },
                            customLabels: ['b', 'b²', 'b³', 'Custom'],
                          ),
                        ),
                      ],
                    ),
                    if (_viewScaleIdx == 4) ...[
                      const SizedBox(height: 8),
                      _buildNumInput(
                        'CUSTOM RESOLUTION',
                        _customViewDim,
                        (v) {
                          _customViewDim = v;
                          _debouncedRender();
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDropdown(
                            'LHS',
                            _lhsRule,
                            _lhsLabels.length - 1,
                            (v) {
                              setState(() => _lhsRule = v!);
                              _debouncedRender();
                            },
                            customLabels: _lhsLabels,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildDropdown(
                            'RHS 1',
                            _rhs1Rule,
                            _rhsLabels.length - 1,
                            (v) {
                              setState(() => _rhs1Rule = v!);
                              _debouncedRender();
                            },
                            customLabels: _rhsLabels,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 48,
                          width: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: _logicOp == 2
                                  ? Theme.of(context).colorScheme.primary
                                  : const Color(0xFF2A2A2A),
                            ),
                            onPressed: () => setState(() {
                              _logicOp = _logicOp == 2 ? 0 : 2;
                              _debouncedRender();
                            }),
                            child: Icon(
                              _logicOp == 2 ? Icons.add_circle : Icons.add,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Opacity(
                            opacity: _logicOp == 2 ? 1.0 : 0.3,
                            child: IgnorePointer(
                              ignoring: _logicOp != 2,
                              child: _buildDropdown(
                                'RHS 2',
                                _rhs2Rule,
                                _rhsLabels.length - 1,
                                (v) {
                                  setState(() => _rhs2Rule = v!);
                                  _debouncedRender();
                                },
                                customLabels: _rhsLabels,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF333333)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'POST-PROCESSING',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDropdown(
                            'TRANSFORMATION',
                            ['NONE', 'ITERATE', 'C_SEQ', 'D_SEQ'].indexOf(_postType),
                            3,
                            (v) {
                              setState(() => _postType = ['NONE', 'ITERATE', 'C_SEQ', 'D_SEQ'][v!]);
                              _debouncedRender();
                            },
                            customLabels: [
                              'Raw',
                              'Iterate a(n)',
                              'C(n) Congruence',
                              'D(n) Diagonal Sum'
                            ],
                          ),
                          if (_postType == 'ITERATE') ...[
                            const SizedBox(height: 8),
                            _buildNumInput('ITERATION DEPTH (k)', _iterK, (v) {
                              _iterK = v;
                              _debouncedRender();
                            }),
                          ],
                          if (_postType == 'C_SEQ' || _postType == 'D_SEQ') ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDropdown(
                                    'LOCAL MAP',
                                    _postGridScaleIdx - 1,
                                    3,
                                    (v) {
                                      setState(() => _postGridScaleIdx = v! + 1);
                                      _debouncedRender();
                                    },
                                    customLabels: ['b', 'b²', 'b³', 'Custom'],
                                  ),
                                ),
                                if (_postGridScaleIdx == 4) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildNumInput('ROWS', _customPostR, (v) {
                                      _customPostR = v;
                                      _debouncedRender();
                                    }),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildNumInput('COLS', _customPostC, (v) {
                                      _customPostC = v;
                                      _debouncedRender();
                                    }),
                                  ),
                                ]
                              ],
                            ),
                          ],
                          if (_postType == 'C_SEQ') ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildNumInput('TARGET (T)', _targetT, (v) {
                                    _targetT = v;
                                    _debouncedRender();
                                  }),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildNumInput('MOD (Mc)', _modMc, (v) {
                                    _modMc = v;
                                    _debouncedRender();
                                  }),
                                ),
                              ],
                            )
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF333333)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'ANIMATION',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDropdown(
                            'MODE',
                            ['modeA', 'modeB', 'modeC'].indexOf(_animMode),
                            2,
                            (v) {
                              setState(() => _animMode = ['modeA', 'modeB', 'modeC'][v!]);
                            },
                            customLabels: ['A: Vary Block', 'B: Vary Base', 'C: Vary Modulo'],
                          ),
                          const SizedBox(height: 8),
                          if (_animMode == 'modeA')
                            _buildNumInput('BLOCK OFFSET', _animPVal, (v) {
                              setState(() => _animPVal = v);
                            }),
                          if (_animMode == 'modeB' || _animMode == 'modeC') ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _buildNumInput('BLOCK (p)', _animPVal, (v) {
                                    setState(() => _animPVal = v);
                                  }),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildNumInput('START', _animStart, (v) {
                                    setState(() => _animStart = v);
                                  }),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildNumInput('END', _animEnd, (v) {
                                    setState(() => _animEnd = v);
                                  }),
                                ),
                              ],
                            )
                          ]
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumInput('TUPLE DEPTH', _tupleK, (v) {
                            _tupleK = v;
                            _debouncedRender();
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _randomizeColors,
                            icon: const Icon(Icons.palette, size: 16),
                            label: const Text('COLOR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2A2A2A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : () => _exportArtifact(false),
                            icon: const Icon(Icons.download),
                            label: const Text('HI-RES PNG'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.secondary,
                            ),
                            onPressed: _isProcessing ? null : () => _exportArtifact(true),
                            icon: const Icon(Icons.animation),
                            label: const Text('BUILD GIF'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    int currentVal,
    int maxVal,
    ValueChanged<int?> onChanged, {
    List<String>? customLabels,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButton<int>(
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF1E1E1E),
            value: currentVal,
            items: List.generate(
              maxVal + 1,
              (i) => DropdownMenuItem(
                value: i,
                child: Text(
                  customLabels != null ? customLabels[i] : 'Rule $i',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildNumInput(String label, int val, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: TextFormField(
            key: ValueKey('$label-$val'),
            initialValue: val.toString(),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(contentPadding: EdgeInsets.zero),
            onChanged: (str) {
              final parsed = int.tryParse(str);
              if (parsed != null && parsed >= 0) {
                onChanged(parsed);
              }
            },
          ),
        ),
      ],
    );
  }
}
