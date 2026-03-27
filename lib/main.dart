import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const UniversalSequencerApp());
}

class UniversalSequencerApp extends StatelessWidget {
  const UniversalSequencerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Tuple Sequence',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        cardColor: const Color(0xFF1A1A24),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF4081),
        ),
      ),
      home: const SequencerWorkspace(),
    );
  }
}

// --- ISOLATE DATA STRUCTURES ---

class EngineConfig {
  final BigInt startN;
  final int bNum;
  final int renderR;
  final int renderC;
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
  final int tupleK; // Added tuple config length

  EngineConfig({
    required this.startN, required this.bNum, required this.renderR,
    required this.renderC, required this.modM, required this.lhsRule,
    required this.rhs1Rule, required this.rhs2Rule, required this.logicOp,
    required this.postType, required this.iterK, required this.postGridR,
    required this.postGridC, required this.targetT, required this.modMc,
    required this.tupleK,
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
    required this.engine, required this.isGif, 
    this.frames = 1, this.animMode = 'modeA',
    this.animStart = 0, this.animEnd = 0, this.animPVal = 0,
  });
}

// --- BACKGROUND ISOLATE LOGIC ---

Future<Uint8List> _backgroundExportTask(ExportConfig eCfg) async {
  if (eCfg.isGif) {
    final animation = img.Image(width: eCfg.engine.renderC, height: eCfg.engine.renderR, numFrames: eCfg.frames);
    
    for (int f = 0; f < eCfg.frames; f++) {
      int currentB = eCfg.engine.bNum;
      int currentM = eCfg.engine.modM;
      BigInt currentStart = eCfg.engine.startN;

      if (eCfg.animMode == 'modeA') {
         currentStart = BigInt.from(eCfg.animPVal * currentB + f) * BigInt.from(eCfg.engine.renderR * eCfg.engine.renderC);
      } else if (eCfg.animMode == 'modeB') {
         currentB = eCfg.animStart + f;
         currentStart = BigInt.from(eCfg.animPVal) * BigInt.from(eCfg.engine.renderR * eCfg.engine.renderC);
      } else if (eCfg.animMode == 'modeC') {
         currentM = eCfg.animStart + f;
         currentStart = BigInt.from(eCfg.animPVal) * BigInt.from(eCfg.engine.renderR * eCfg.engine.renderC);
      }

      final modEngine = EngineConfig(
        startN: currentStart, bNum: currentB, renderR: eCfg.engine.renderR, renderC: eCfg.engine.renderC,
        modM: currentM, lhsRule: eCfg.engine.lhsRule, rhs1Rule: eCfg.engine.rhs1Rule,
        rhs2Rule: eCfg.engine.rhs2Rule, logicOp: eCfg.engine.logicOp, postType: eCfg.engine.postType, 
        iterK: eCfg.engine.iterK, postGridR: eCfg.engine.postGridR, postGridC: eCfg.engine.postGridC,
        targetT: eCfg.engine.targetT, modMc: eCfg.engine.modMc, tupleK: eCfg.engine.tupleK
      );

      final buffer = _calculateMathBuffer(modEngine);
      final frame = animation.frames[f];
      for (int i = 0; i < buffer.length; i++) {
        int r = i ~/ modEngine.renderC;
        int c = i % modEngine.renderC;
        int col = (buffer[i] * 255) ~/ (modEngine.modM > 1 ? modEngine.modM - 1 : 1);
        frame.setPixelRgba(c, r, col, col, col, 255);
      }
    }
    return img.encodeGif(animation);
  } else {
    final buffer = _calculateMathBuffer(eCfg.engine);
    final image = img.Image(width: eCfg.engine.renderC, height: eCfg.engine.renderR);
    for (int i = 0; i < buffer.length; i++) {
      int r = i ~/ eCfg.engine.renderC;
      int c = i % eCfg.engine.renderC;
      int col = (buffer[i] * 255) ~/ (eCfg.engine.modM > 1 ? eCfg.engine.modM - 1 : 1);
      image.setPixelRgba(c, r, col, col, col, 255);
    }
    return img.encodePng(image);
  }
}

Future<Uint8List> _runMathEngineLive(EngineConfig config) async {
  final buffer = _calculateMathBuffer(config);
  final pixels = Uint8List(config.renderR * config.renderC * 4);
  for (int i = 0; i < buffer.length; i++) {
    int idx = i * 4;
    int col = (buffer[i] * 255) ~/ (config.modM > 1 ? config.modM - 1 : 1);
    pixels[idx] = col;
    pixels[idx + 1] = col;
    pixels[idx + 2] = col;
    pixels[idx + 3] = 255;
  }
  return pixels;
}

Uint8List _calculateMathBuffer(EngineConfig config) {
  final buffer = Uint8List(config.renderR * config.renderC);
  final bigB = BigInt.from(config.bNum);

  for (int r = 0; r < config.renderR; r++) {
    for (int c = 0; c < config.renderC; c++) {
      BigInt n = config.startN + BigInt.from(r * config.renderC + c);
      int result = 0;

      if (config.postType == 'NONE') {
        result = _solveForN(n, bigB, config);
      } 
      else if (config.postType == 'ITERATE') {
        result = _solveForN(n, bigB, config);
        for (int i = 1; i < config.iterK; i++) {
          result = _solveForN(BigInt.from(result), bigB, config);
        }
      }
      else if (config.postType == 'C_SEQ') {
        BigInt blockSize = BigInt.from(config.postGridR * config.postGridC);
        BigInt block = n ~/ blockSize;
        BigInt idx = n % blockSize;
        int subR = (idx ~/ BigInt.from(config.postGridC)).toInt();
        int subC = (idx % BigInt.from(config.postGridC)).toInt();
        
        int count = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            int nr = subR + dr, nc = subC + dc;
            if (nr >= 0 && nr < config.postGridR && nc >= 0 && nc < config.postGridC) {
              BigInt nPrime = block * blockSize + BigInt.from(nr * config.postGridC + nc);
              if (_solveForN(nPrime, bigB, config) % config.modMc == config.targetT) count++;
            }
          }
        }
        result = count;
      }
      else if (config.postType == 'D_SEQ') {
        BigInt blockSize = BigInt.from(config.postGridR * config.postGridC);
        BigInt baseN = n * blockSize;
        int minDim = math.min(config.postGridR, config.postGridC);
        int sum = 0;
        for (int i = 0; i < minDim; i++) {
          BigInt nPrime = baseN + BigInt.from(i * config.postGridC + i);
          sum += _solveForN(nPrime, bigB, config);
        }
        result = sum;
      }

      buffer[r * config.renderC + c] = result % config.modM;
    }
  }
  return buffer;
}

// MULTI-DIMENSIONAL DP ENGINE
int _solveForN(BigInt n, BigInt bigB, EngineConfig config) {
  int b = config.bNum;
  int k = 0;
  
  if (n == BigInt.zero) { k = 1; } 
  else {
    BigInt t = n;
    while (t > BigInt.zero) { k++; t = t ~/ bigB; }
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
  for (int w = k + 1; w < d.length; w++) d[w] = d[(w - 1) % k + 1];

  int totalWays = 0;
  int lhs = config.lhsRule;

  // ENGINE 1: GLOBAL DP (Rule 14 in original)
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
              if (config.logicOp == 1) conditionMet = c1 && _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
              else if (config.logicOp == 2) conditionMet = c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);

              if (conditionMet) {
                int nextC = Ci + xNext;
                if (nextC <= Sigma) { nextDp[nextC] += dp[Ci]; hasState = true; }
              }
            }
          }
          if (!hasState) { possible = false; break; }
          List<int> tArr = dp; dp = nextDp; nextDp = tArr;
        }
        if (possible) totalWays += dp[Sigma];
      }
    }
    return totalWays;
  }

  // ENGINE 2: COMPLEX Z-PLANE (Rules 15, 16, 17, 18)
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
          double dist = math.sqrt(math.pow(xiX - xNextX, 2) + math.pow(xiY - xNextY, 2));
          int val = 0;
          
          if (lhs == 15) val = dist.toInt(); // Exact mapping to int
          else if (lhs == 16) val = dist.floor();
          else if (lhs == 17) val = dist.ceil();
          else if (lhs == 18) val = dist.round();

          bool c1 = _evaluateRHS(config.rhs1Rule, val, di, dNext, b);
          bool conditionMet = c1;
          if (config.logicOp == 1) conditionMet = c1 && _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
          else if (config.logicOp == 2) conditionMet = c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);

          if (conditionMet) nextV[nextState] += v[state];
        }
      }
      List<int> tArr = v; v = nextV; nextV = tArr;
    }
    for (int i = 0; i < numStates; i++) totalWays += v[i];
    return totalWays;
  }

  // ENGINE 3: ACCUMULATOR DP (Rule 7)
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
          if (config.logicOp == 1) conditionMet = c1 && _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
          else if (config.logicOp == 2) conditionMet = c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);

          if (conditionMet) nextV[val] += v[acc];
        }
      }
      List<int> tArr = v; v = nextV; nextV = tArr;
    }
    for (int i = 0; i < b; i++) totalWays += v[i];
    return totalWays;
  }

  // ENGINE 4: LOOKBACK / LOOKAHEAD (Rules 10, 11)
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
            if (lhs == 10) val = ((a - bVal).abs() - (bVal - c).abs()).abs(); // prev=a, xi=bVal, next=c
            else if (lhs == 11) val = (a - bVal - c).abs(); // xi=a, next=bVal, nnext=c
            
            bool c1 = _evaluateRHS(config.rhs1Rule, val, di, dNext, b);
            bool conditionMet = c1;
            if (config.logicOp == 1) conditionMet = c1 && _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
            else if (config.logicOp == 2) conditionMet = c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);

            if (conditionMet) nextV[bVal * b + c] += v[a * b + bVal];
          }
        }
      }
      List<int> tArr = v; v = nextV; nextV = tArr;
    }
    for (int i = 0; i < numStates; i++) totalWays += v[i];
    return totalWays;
  }

  // ENGINE 5: STANDARD 1D DP (Rules 0-6, 8, 9, 12, 13, 19-35)
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
            if (config.logicOp == 1) conditionMet = c1 && _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
            else if (config.logicOp == 2) conditionMet = c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);

            if (conditionMet) nextV[xNext] += v[xi];
          }
        }
        List<int> tArr = v; v = nextV; nextV = tArr;
      }
      for (int i = 0; i < b; i++) totalWays += v[i];
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
        if (config.logicOp == 1) conditionMet = c1 && _evaluateRHS(config.rhs2Rule, val, di, dNext, b);
        else if (config.logicOp == 2) conditionMet = c1 || _evaluateRHS(config.rhs2Rule, val, di, dNext, b);

        if (conditionMet) nextV[xNext] += v[xi];
      }
    }
    List<int> tArr = v; v = nextV; nextV = tArr;
  }

  for (int i = 0; i < b; i++) totalWays += v[i];
  return totalWays;
}

int _evaluateLHS(int rule, int xi, int xNext, int b, int di, int dNext) {
  switch (rule) {
    case 0: return (xi - xNext).abs();
    // Rule 1 is handled in the Engine directly (needs x1 context)
    case 2: return (xNext - xi + b) % b;
    case 3: return (xi + xNext) % b;
    case 4: return xi > xNext ? xi : xNext;
    case 5: return xi < xNext ? xi : xNext;
    case 6: return (xi ^ xNext) % b;
    // Rule 7 handled in Engine (Accumulator)
    case 8: return (xi * xNext) % b;
    case 9: return ((b - 1 - xi) - xNext).abs();
    // Rules 10, 11 handled in Engine (Lookback)
    case 12: return ((xi * xi) % b - xNext).abs();
    // Rule 14 handled in Engine (Global)
    // Rules 15-18 handled in Engine (Complex)
    
    // Extrapolated rules starting at 19 for standard Engine
    case 19: return ((xi * xi * xi) + (xNext * xNext * xNext)) % b;
    case 20: return ((xi * xi) - (xNext * xNext)).abs();
    case 21: int a=xi, c=xNext; while(c!=0){int t=c; c=a%c; a=t;} return a;
    case 22: int a2=xi, c2=xNext; int gcd=1; while(c2!=0){int t=c2; c2=a2%c2; a2=t;} gcd=a2; return gcd==0 ? 0 : ((xi*xNext)~/gcd) % b;
    case 23: return (xi - (b~/2)).abs() + (xNext - (b~/2)).abs();
    case 24: return (xi | xNext) % b;
    case 25: return (xi & xNext) % b;
    case 26: return ((xi << 1) ^ xNext) % b;
    case 27: return ((xi * (xi + 1)) ~/ 2) % b;
    case 28: return ((xi * xi) + (xi * xNext) + (xNext * xNext)) % b;
    case 29: return ((xi * di) + (xNext * dNext)) % b;
    case 30: return ((xi + 1) * (xNext + 1)) % b;
    default: return (xi - xNext).abs();
  }
}

bool _evaluateRHS(int rule, int val, int di, int dNext, int b) {
  switch (rule) {
    case 0: return val == di;
    case 1: return val == (b - 1 - di);
    case 2: return val <= di;
    case 3: return val >= di;
    case 4: return val != di;
    case 5: return (val % 2) == (di % 2);
    case 6: return val == (b ~/ 2);
    case 7: return val < di;
    case 8: return val > di;
    case 9: return val == (di + 1) % b;
    case 10: return val == (di + dNext) % b;
    case 11: return val == (di * dNext) % b;
    
    // Extrapolated RHS rules
    case 12: return (val % 3) == (di % 3);
    case 13: return (val % 4) == (di % 4);
    case 14: return val == ((di * di) % b);
    case 15: return val == (di - dNext).abs();
    case 16: return val == (di > dNext ? di : dNext);
    case 17: return val == (di < dNext ? di : dNext);
    case 18: return val == (di ^ dNext);
    case 19: return val > (b ~/ 2);
    case 20: return val < (b ~/ 2);
    case 21: return val == (b - di) % b;
    case 22: return val != (di + 1) % b;
    case 23: return val <= (di + (b ~/ 2)) % b;
    case 24: return val >= (di - (b ~/ 2)) % b;
    default: return val == di;
  }
}

// --- UI LAYER ---

class SequencerWorkspace extends StatefulWidget {
  const SequencerWorkspace({super.key});
  @override
  State<SequencerWorkspace> createState() => _SequencerWorkspaceState();
}

class _SequencerWorkspaceState extends State<SequencerWorkspace> {
  ui.Image? _renderedGrid;
  bool _isProcessing = false;
  
  // Math Params
  int _bNum = 3;
  int _modM = 4;
  int _pVal = 0;
  int _lhsRule = 0;
  int _rhs1Rule = 0;
  int _rhs2Rule = 1;
  int _logicOp = 0;
  int _tupleK = 1;
  
  // View Params
  int _viewScaleIdx = 2; // 1:b, 2:b^2, 3:b^3
  int _customViewR = 100;
  int _customViewC = 100;

  // Post Proc Params
  String _postType = 'NONE';
  int _iterK = 2;
  int _postGridScaleIdx = 1;
  int _customPostR = 10;
  int _customPostC = 10;
  int _targetT = 0;
  int _modMc = 4;

  // Anim Params
  String _animMode = 'modeA';
  int _animStart = 2;
  int _animEnd = 6;
  int _animPVal = 0;

  final List<String> _lhsLabels = [
    "0: | x_i - x_(i+1) |",
    "1: | x_1 - x_(i+1) | (Anchor)",
    "2: (x_(i+1) - x_i + b) mod b",
    "3: (x_i + x_(i+1)) mod b",
    "4: max(x_i, x_(i+1))",
    "5: min(x_i, x_(i+1))",
    "6: (x_i ⊕ x_(i+1)) mod b",
    "7: ||..|x_1 - x_2|..| - x_(i+1)| (Accumulator)",
    "8: (x_i × x_(i+1)) mod b",
    "9: |(b - 1 - x_i) - x_(i+1)|",
    "10: ||x_(i-1) - x_i| - |x_i - x_(i+1)||",
    "11: |x_i - x_(i+1) - x_(i+2)|",
    "12: |(x_i)² mod b - x_(i+1)|",
    "13: [OMITTED CUSTOM JS]",
    "14: ||x_1-..-x_i| - |x_(i+1)-..-x_(k+1)|| (Global)",
    "15: Complex Z: Exact |z_i - z_(i+1)|",
    "16: Complex Z1: Floor(|z_i - z_(i+1)|)",
    "17: Complex Z2: Ceil(|z_i - z_(i+1)|)",
    "18: Complex Z3: Round(|z_i - z_(i+1)|)",
    "19: Sum of Cubes mod b",
    "20: Diff of Squares",
    "21: GCD(xi, x_next)",
    "22: LCM(xi, x_next) mod b",
    "23: Distance from Center",
    "24: Bitwise OR mod b",
    "25: Bitwise AND mod b",
    "26: Left Shift XOR mod b",
    "27: Triangular Number mod b",
    "28: Quadratic Form mod b",
    "29: D-weighted sum mod b",
    "30: Shifted Product mod b"
  ];

  @override
  void initState() {
    super.initState();
    _requestRender();
  }

  int _getDim(int scaleType, int customDim) {
    if (scaleType == 4) return customDim;
    return math.pow(_bNum, scaleType).toInt();
  }

  Future<void> _requestRender() async {
    setState(() => _isProcessing = true);
    
    int renderR = _getDim(_viewScaleIdx, _customViewR);
    int renderC = _getDim(_viewScaleIdx, _customViewC);
    
    if (renderR > 400) renderR = 400;
    if (renderC > 400) renderC = 400;

    int postR = _getDim(_postGridScaleIdx, _customPostR);
    int postC = _getDim(_postGridScaleIdx, _customPostC);
    
    EngineConfig cfg = EngineConfig(
      startN: BigInt.from(_pVal * renderR * renderC), bNum: _bNum, renderR: renderR,
      renderC: renderC, modM: _modM, lhsRule: _lhsRule,
      rhs1Rule: _rhs1Rule, rhs2Rule: _rhs2Rule, logicOp: _logicOp,
      postType: _postType, iterK: _iterK, postGridR: postR, postGridC: postC,
      targetT: _targetT, modMc: _modMc, tupleK: _tupleK
    );

    Uint8List pixels = await compute(_runMathEngineLive, cfg);
    ui.decodeImageFromPixels(pixels, renderC, renderR, ui.PixelFormat.rgba8888, (img) {
      if(mounted) setState(() { _renderedGrid = img; _isProcessing = false; });
    });
  }

  Future<void> _exportArtifact(bool asGif) async {
    setState(() => _isProcessing = true);
    
    int renderR = _getDim(_viewScaleIdx, _customViewR);
    int renderC = _getDim(_viewScaleIdx, _customViewC);
    
    if (renderR > 1000) renderR = 1000;
    if (renderC > 1000) renderC = 1000;

    int postR = _getDim(_postGridScaleIdx, _customPostR);
    int postC = _getDim(_postGridScaleIdx, _customPostC);

    int frames = 1;
    if (asGif) {
      if (_animMode == 'modeA') frames = _bNum;
      else if (_animMode == 'modeB') frames = (_animEnd - _animStart) + 1;
      else if (_animMode == 'modeC') frames = (_animEnd - _animStart) + 1;
    }
    
    EngineConfig baseCfg = EngineConfig(
      startN: BigInt.from(_pVal * renderR * renderC), bNum: _bNum, renderR: renderR,
      renderC: renderC, modM: _modM, lhsRule: _lhsRule,
      rhs1Rule: _rhs1Rule, rhs2Rule: _rhs2Rule, logicOp: _logicOp,
      postType: _postType, iterK: _iterK, postGridR: postR, postGridC: postC,
      targetT: _targetT, modMc: _modMc, tupleK: _tupleK
    );

    ExportConfig eCfg = ExportConfig(
      engine: baseCfg, isGif: asGif, frames: frames, animMode: _animMode,
      animStart: _animStart, animEnd: _animEnd, animPVal: _animPVal
    );

    Uint8List resultBytes = await compute(_backgroundExportTask, eCfg);
    
    String ext = asGif ? "gif" : "png";
    final tempDir = await getTemporaryDirectory();
    final file = await File('${tempDir.path}/sequence_export.$ext').create();
    await file.writeAsBytes(resultBytes);
    
    if(mounted) setState(() => _isProcessing = false);

    await Share.shareXFiles([XFile(file.path)], text: 'Exported Native Sequence');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Universal Sequencer Native')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 800;
          List<Widget> children = [
            Expanded(flex: 3, child: _buildControls()),
            const SizedBox(width: 20, height: 20),
            Expanded(flex: 5, child: _buildViewer()),
          ];
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: isDesktop 
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: children)
              : ListView(children: children),
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ruleset Logic', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyan)),
              const Divider(),
              _buildDropdown('LHS Operation', _lhsRule, 30, (v) { setState(() => _lhsRule = v!); _requestRender(); }, customLabels: _lhsLabels),
              const SizedBox(height: 12),
              _buildDropdown('RHS Constraint 1', _rhs1Rule, 24, (v) { setState(() => _rhs1Rule = v!); _requestRender(); }),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildDropdown('Logical Pairing', _logicOp, 2, (v) { setState(() => _logicOp = v!); _requestRender(); }, customLabels: ['None', 'AND', 'OR'])),
                  const SizedBox(width: 10),
                  Expanded(child: Opacity(
                    opacity: _logicOp == 0 ? 0.3 : 1.0,
                    child: _buildDropdown('RHS Constraint 2', _rhs2Rule, 24, (v) { if(_logicOp!=0) { setState(() => _rhs2Rule = v!); _requestRender(); } })
                  )),
                ],
              ),
              const SizedBox(height: 20),
              
              const Text('Sequence Post-Processing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyan)),
              const Divider(),
              _buildDropdown('Transformation Type', ['NONE', 'ITERATE', 'C_SEQ', 'D_SEQ'].indexOf(_postType), 3, (v) { 
                setState(() => _postType = ['NONE', 'ITERATE', 'C_SEQ', 'D_SEQ'][v!]); _requestRender(); 
              }, customLabels: ['None (Raw)', 'Iterate a(n)', 'C(n) Congruence', 'D(n) Diagonal Sum']),
              
              if (_postType == 'ITERATE') ...[
                const SizedBox(height: 10),
                _buildNumInput('Iteration Depth (k)', _iterK, (v) { setState(() => _iterK = v); _requestRender(); }),
              ],

              if (_postType == 'C_SEQ' || _postType == 'D_SEQ') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildDropdown('Local Map Size', _postGridScaleIdx - 1, 3, (v) { setState(() => _postGridScaleIdx = v! + 1); _requestRender(); }, customLabels: ['Base (b)', 'Base² (b²)', 'Base³ (b³)', 'Custom'])),
                    if (_postGridScaleIdx == 4) ...[
                      const SizedBox(width: 10),
                      Expanded(child: _buildNumInput('Rows', _customPostR, (v) { setState(() => _customPostR = v); _requestRender(); })),
                      const SizedBox(width: 10),
                      Expanded(child: _buildNumInput('Cols', _customPostC, (v) { setState(() => _customPostC = v); _requestRender(); })),
                    ]
                  ],
                ),
              ],
              
              if (_postType == 'C_SEQ') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildNumInput('Target Congruence (T)', _targetT, (v) { setState(() => _targetT = v); _requestRender(); })),
                    const SizedBox(width: 10),
                    Expanded(child: _buildNumInput('Modulo (Mc)', _modMc, (v) { setState(() => _modMc = v); _requestRender(); })),
                  ],
                )
              ],

              const SizedBox(height: 20),
              const Text('GIF Animator Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyan)),
              const Divider(),
              _buildDropdown('Animation Mode', ['modeA', 'modeB', 'modeC'].indexOf(_animMode), 2, (v) { 
                setState(() => _animMode = ['modeA', 'modeB', 'modeC'][v!]); 
              }, customLabels: ['A: Fixed Base, Vary Block', 'B: Fixed Block, Vary Base', 'C: Fixed B & P, Vary Modulo']),
              const SizedBox(height: 10),
              
              if (_animMode == 'modeA')
                _buildNumInput('Block (p) Offset', _animPVal, (v) { setState(() => _animPVal = v); }),
              
              if (_animMode == 'modeB' || _animMode == 'modeC') ...[
                Row(
                  children: [
                    Expanded(child: _buildNumInput('Block (p)', _animPVal, (v) { setState(() => _animPVal = v); })),
                    const SizedBox(width: 10),
                    Expanded(child: _buildNumInput('Start Value', _animStart, (v) { setState(() => _animStart = v); })),
                    const SizedBox(width: 10),
                    Expanded(child: _buildNumInput('End Value', _animEnd, (v) { setState(() => _animEnd = v); })),
                  ],
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewer() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Interactive Viewer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyan)),
            const Divider(),
            Row(
              children: [
                Expanded(child: _buildNumInput('Base (b)', _bNum, (v) { setState(() => _bNum = v); _requestRender(); })),
                const SizedBox(width: 10),
                Expanded(child: _buildNumInput('Modulo (m)', _modM, (v) { setState(() => _modM = v); _requestRender(); })),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildNumInput('Range Block (p)', _pVal, (v) { setState(() => _pVal = v); _requestRender(); })),
                const SizedBox(width: 10),
                Expanded(child: _buildNumInput('Tuple Config (k+C)', _tupleK, (v) { setState(() => _tupleK = v); _requestRender(); })),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildDropdown('Global Render Scale', _viewScaleIdx - 1, 3, (v) { setState(() => _viewScaleIdx = v! + 1); _requestRender(); }, customLabels: ['b × b', 'b² × b²', 'b³ × b³', 'Custom Limit'])),
                if (_viewScaleIdx == 4) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _buildNumInput('Rows (R)', _customViewR, (v) { setState(() => _customViewR = v); _requestRender(); })),
                  const SizedBox(width: 10),
                  Expanded(child: _buildNumInput('Cols (C)', _customViewC, (v) { setState(() => _customViewC = v); _requestRender(); })),
                ]
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade800), color: Colors.black),
                    child: _isProcessing 
                        ? const Center(child: CircularProgressIndicator())
                        : _renderedGrid != null 
                            ? RawImage(image: _renderedGrid, fit: BoxFit.fill, filterQuality: FilterQuality.none)
                            : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: ElevatedButton(
                  onPressed: _isProcessing ? null : () => _exportArtifact(false),
                  child: const Text('Download High-Res (PNG)'),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondary),
                  onPressed: _isProcessing ? null : () => _exportArtifact(true),
                  child: const Text('Compile Animation (GIF)'),
                )),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, int currentVal, int maxVal, ValueChanged<int?> onChanged, {List<String>? customLabels}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFF22222D), borderRadius: BorderRadius.circular(8)),
          child: DropdownButton<int>(
            isExpanded: true, underline: const SizedBox(),
            value: currentVal,
            items: List.generate(maxVal + 1, (i) => DropdownMenuItem(value: i, child: Text(customLabels != null ? customLabels[i] : 'Rule $i', style: const TextStyle(fontSize: 14)))),
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
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: val.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            filled: true, fillColor: const Color(0xFF22222D),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          ),
          onChanged: (str) {
            int? parsed = int.tryParse(str);
            if (parsed != null && parsed >= 0) onChanged(parsed);
          },
        ),
      ],
    );
  }
}
