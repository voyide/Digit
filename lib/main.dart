import 'dart:io';
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
          contentPadding: EdgeInsets.all(8),
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

// --- CORE DATA STRUCTURES ---

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
  final int tupleK;
  final Uint32List palette; 

  EngineConfig({
    required this.startN, required this.bNum, required this.renderR, required this.renderC,
    required this.modM, required this.lhsRule, required this.rhs1Rule, required this.rhs2Rule,
    required this.logicOp, required this.postType, required this.iterK, required this.postGridR,
    required this.postGridC, required this.targetT, required this.modMc, required this.tupleK,
    required this.palette,
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
    required this.engine, required this.isGif, this.frames = 1,
    this.animMode = 'modeA', this.animStart = 0, this.animEnd = 0, this.animPVal = 0,
  });
}

class ProgressUpdate {
  final Uint8List pixels;
  final double progress;
  ProgressUpdate(this.pixels, this.progress);
}

// --- BACKGROUND ISOLATE LOGIC ---

void _liveRenderIsolate(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort);

  port.listen((message) {
    if (message is EngineConfig) {
      final config = message;
      final pixels = Uint8List(config.renderR * config.renderC * 4);
      int reportStep = math.max(1, config.renderR ~/ 20); 

      final buffer = _calculateMathBuffer(config);

      for (int r = 0; r < config.renderR; r++) {
        for (int c = 0; c < config.renderC; c++) {
          int modVal = buffer[r * config.renderC + c];
          int colorData = config.palette[modVal];
          
          int idx = (r * config.renderC + c) * 4;
          pixels[idx] = (colorData >> 16) & 0xFF;     
          pixels[idx + 1] = (colorData >> 8) & 0xFF;  
          pixels[idx + 2] = colorData & 0xFF;         
          pixels[idx + 3] = 255;                      
        }

        if (r % reportStep == 0 || r == config.renderR - 1) {
          mainPort.send(ProgressUpdate(Uint8List.fromList(pixels), (r + 1) / config.renderR));
        }
      }
    }
  });
}

Future<Uint8List> _backgroundExportTask(ExportConfig eCfg) async {
  if (eCfg.isGif) {
    img.Image? animation;
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
        modM: currentM, lhsRule: eCfg.engine.lhsRule, rhs1Rule: eCfg.engine.rhs1Rule, rhs2Rule: eCfg.engine.rhs2Rule, 
        logicOp: eCfg.engine.logicOp, postType: eCfg.engine.postType, iterK: eCfg.engine.iterK, postGridR: eCfg.engine.postGridR, 
        postGridC: eCfg.engine.postGridC, targetT: eCfg.engine.targetT, modMc: eCfg.engine.modMc, tupleK: eCfg.engine.tupleK,
        palette: eCfg.engine.palette,
      );

      final buffer = _calculateMathBuffer(modEngine);
      final frame = img.Image(width: modEngine.renderC, height: modEngine.renderR, numChannels: 4);
      
      for (int i = 0; i < buffer.length; i++) {
        int r = i ~/ modEngine.renderC;
        int c = i % modEngine.renderC;
        int colorData = modEngine.palette[buffer[i]];
        frame.setPixelRgba(c, r, (colorData >> 16) & 0xFF, (colorData >> 8) & 0xFF, colorData & 0xFF, 255);
      }

      if (animation == null) animation = frame;
      else animation.addFrame(frame);
    }
    return img.encodeGif(animation!);
  } else {
    final buffer = _calculateMathBuffer(eCfg.engine);
    final image = img.Image(width: eCfg.engine.renderC, height: eCfg.engine.renderR, numChannels: 4);

    for (int i = 0; i < buffer.length; i++) {
      int r = i ~/ eCfg.engine.renderC;
      int c = i % eCfg.engine.renderC;
      int colorData = eCfg.engine.palette[buffer[i]];
      image.setPixelRgba(c, r, (colorData >> 16) & 0xFF, (colorData >> 8) & 0xFF, colorData & 0xFF, 255);
    }
    return img.encodePng(image);
  }
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

// FULL MULTI-DIMENSIONAL DP ENGINE
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
          
          if (lhs == 15) val = dist.toInt(); 
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
            if (lhs == 10) val = ((a - bVal).abs() - (bVal - c).abs()).abs(); 
            else if (lhs == 11) val = (a - bVal - c).abs(); 
            
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
    case 2: return (xNext - xi + b) % b;
    case 3: return (xi + xNext) % b;
    case 4: return xi > xNext ? xi : xNext;
    case 5: return xi < xNext ? xi : xNext;
    case 6: return (xi ^ xNext) % b;
    case 8: return (xi * xNext) % b;
    case 9: return ((b - 1 - xi) - xNext).abs();
    case 12: return ((xi * xi) % b - xNext).abs();
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
  double _renderProgress = 0.0;
  bool _isProcessing = false;
  Isolate? _renderIsolate;
  SendPort? _isolateSendPort;
  
  // Math Params
  int _bNum = 3;
  int _modM = 4;
  int _pVal = 0;
  int _lhsRule = 0;
  int _rhs1Rule = 0;
  int _rhs2Rule = 1;
  int _logicOp = 0;
  int _tupleK = 1;
  bool _showRhs2 = false;
  
  int _viewScaleIdx = 2; 
  int _customViewDim = 100;
  
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

  double _hueShift = 0.0;
  late Uint32List _currentPalette;

  final List<String> _lhsLabels = [
    "0: | xi - x(i+1) |", "1: Anchor | x1 - x(i+1) |", "2: (x(i+1) - xi + b) % b", "3: (xi + x(i+1)) % b", "4: max(xi, x(i+1))", "5: min(xi, x(i+1))",
    "6: xi ⊕ x(i+1)", "7: Accumulator Drop", "8: (xi × x(i+1)) % b", "9: |(b - 1 - xi) - x(i+1)|", "10: Lookback |xi-1 - xi|", "11: Lookahead |xi - x(i+2)|",
    "12: |(xi)² % b - x(i+1)|", "13: [OMITTED]", "14: Global Structure", "15: Complex Z Exact", "16: Complex Z Floor", "17: Complex Z Ceil", "18: Complex Z Round",
    "19: Sum of Cubes", "20: Diff of Squares", "21: GCD", "22: LCM", "23: Center Dist", "24: Bitwise OR", "25: Bitwise AND", "26: L-Shift XOR",
    "27: Triangular Num", "28: Quadratic Form", "29: D-weighted sum", "30: Shifted Product"
  ];

  final List<String> _rhsLabels = [
    "0: = di", "1: = b - 1 - di", "2: ≤ di", "3: ≥ di", "4: ≠ di", "5: ≡ di (mod 2)", "6: = floor(b/2)", "7: < di", "8: > di", "9: = (di + 1) % b",
    "10: = (di + d(i+1)) % b", "11: = (di × d(i+1)) % b", "12: ≡ di (mod 3)", "13: ≡ di (mod 4)", "14: = (di)² % b", "15: = |di - d(i+1)|",
    "16: = max(di, d(i+1))", "17: = min(di, d(i+1))", "18: = di ⊕ d(i+1)", "19: > floor(b/2)", "20: < floor(b/2)", "21: = (b - di) % b",
    "22: ≠ (di + 1) % b", "23: ≤ (di + b/2) % b", "24: ≥ (di - b/2) % b"
  ];

  @override
  void initState() {
    super.initState();
    _generatePalette();
    _initIsolateAndRender();
  }

  void _generatePalette() {
    _currentPalette = Uint32List(_modM);
    _currentPalette[0] = 0xFF000000; 
    for (int i = 1; i < _modM; i++) {
      double hue = (_hueShift + (i * 360 / _modM)) % 360;
      Color c = HSLColor.fromAHSL(1.0, hue, 0.85, 0.55).toColor();
      _currentPalette[i] = (c.red << 16) | (c.green << 8) | c.blue;
    }
  }

  void _randomizeColors() {
    _hueShift = math.Random().nextDouble() * 360.0;
    _generatePalette();
    _triggerRender();
  }

  int _getDim(int scaleIdx, int customDim) {
    if (scaleIdx == 4) return customDim;
    return math.pow(_bNum, scaleIdx).toInt();
  }

  Future<void> _initIsolateAndRender() async {
    final receivePort = ReceivePort();
    _renderIsolate = await Isolate.spawn(_liveRenderIsolate, receivePort.sendPort);
    
    receivePort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        _triggerRender();
      } else if (message is ProgressUpdate) {
        int dim = _getDim(_viewScaleIdx, _customViewDim);
        if (dim > 400) dim = 400; 
        ui.decodeImageFromPixels(message.pixels, dim, dim, ui.PixelFormat.rgba8888, (img) {
          if (mounted) {
            setState(() {
              _renderedGrid = img;
              _renderProgress = message.progress;
              if (_renderProgress >= 1.0) _isProcessing = false;
            });
          }
        });
      }
    });
  }

  void _triggerRender() {
    if (_isolateSendPort == null) return;
    setState(() { _isProcessing = true; _renderProgress = 0.0; });
    
    int dim = _getDim(_viewScaleIdx, _customViewDim);
    if (dim > 400) dim = 400; 
    
    int postR = _getDim(_postGridScaleIdx, _customPostR);
    int postC = _getDim(_postGridScaleIdx, _customPostC);

    _isolateSendPort!.send(EngineConfig(
      startN: BigInt.from(_pVal * dim * dim), bNum: _bNum, renderR: dim, renderC: dim, modM: _modM, 
      lhsRule: _lhsRule, rhs1Rule: _rhs1Rule, rhs2Rule: _rhs2Rule, logicOp: _logicOp, postType: _postType, 
      iterK: _iterK, postGridR: postR, postGridC: postC, targetT: _targetT, modMc: _modMc, tupleK: _tupleK, 
      palette: _currentPalette,
    ));
  }

  Future<void> _exportArtifact(bool asGif) async {
    setState(() { _isProcessing = true; _renderProgress = 0.0; });
    
    int dim = _getDim(_viewScaleIdx, _customViewDim);
    if (dim > 8192) dim = 8192; 
    
    int postR = _getDim(_postGridScaleIdx, _customPostR);
    int postC = _getDim(_postGridScaleIdx, _customPostC);

    EngineConfig baseCfg = EngineConfig(
      startN: BigInt.from(_pVal * dim * dim), bNum: _bNum, renderR: dim, renderC: dim, modM: _modM, 
      lhsRule: _lhsRule, rhs1Rule: _rhs1Rule, rhs2Rule: _rhs2Rule, logicOp: _logicOp, postType: _postType, 
      iterK: _iterK, postGridR: postR, postGridC: postC, targetT: _targetT, modMc: _modMc, tupleK: _tupleK, 
      palette: _currentPalette,
    );

    int frames = 1;
    if (asGif) {
      if (_animMode == 'modeA') frames = _bNum;
      else if (_animMode == 'modeB' || _animMode == 'modeC') frames = (_animEnd - _animStart) + 1;
    }

    ExportConfig eCfg = ExportConfig(
      engine: baseCfg, isGif: asGif, frames: frames, animMode: _animMode,
      animStart: _animStart, animEnd: _animEnd, animPVal: _animPVal
    );

    Uint8List resultBytes = await compute(_backgroundExportTask, eCfg);
    
    String ext = asGif ? "gif" : "png";
    final tempDir = await getTemporaryDirectory();
    final file = await File('${tempDir.path}/SEQ_b${_bNum}_m${_modM}.$ext').create();
    await file.writeAsBytes(resultBytes);
    
    if(mounted) setState(() { _isProcessing = false; _renderProgress = 1.0; });
    await Share.shareXFiles([XFile(file.path)], text: 'Universal Sequence Render');
  }

  @override
  void dispose() {
    _renderIsolate?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    RawImage(image: _renderedGrid, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                  if (_isProcessing)
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: LinearProgressIndicator(
                        value: _renderProgress,
                        backgroundColor: Colors.transparent,
                        color: Theme.of(context).colorScheme.primary,
                        minHeight: 4,
                      ),
                    ),
                  Positioned(
                    bottom: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.black87,
                      child: Text(
                        'b:$_bNum | m:$_modM | r:$_lhsRule',
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
                        Expanded(child: _buildNumInput('BASE', _bNum, (v) { _bNum = v; _triggerRender(); })),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumInput('MOD', _modM, (v) { _modM = v; _generatePalette(); _triggerRender(); })),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumInput('RANGE', _pVal, (v) { _pVal = v; _triggerRender(); })),
                        const SizedBox(width: 8),
                        Expanded(child: _buildDropdown('GRID', _viewScaleIdx - 1, 3, (v) { _viewScaleIdx = v! + 1; _triggerRender(); }, customLabels: ['b', 'b²', 'b³', '8K'])),
                      ],
                    ),
                    if (_viewScaleIdx == 4) ...[
                      const SizedBox(height: 8),
                      _buildNumInput('CUSTOM RESOLUTION (MAX 8192)', _customViewDim, (v) { _customViewDim = v; _triggerRender(); }),
                    ],
                    
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(flex: 2, child: _buildDropdown('LHS', _lhsRule, _lhsLabels.length - 1, (v) { _lhsRule = v!; _triggerRender(); }, customLabels: _lhsLabels)),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: _buildDropdown('RHS 1', _rhs1Rule, _rhsLabels.length - 1, (v) { _rhs1Rule = v!; _triggerRender(); }, customLabels: _rhsLabels)),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 48, width: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: _showRhs2 ? Theme.of(context).colorScheme.primary : const Color(0xFF2A2A2A),
                            ),
                            onPressed: () => setState(() { _showRhs2 = !_showRhs2; _logicOp = _showRhs2 ? 1 : 0; _triggerRender(); }),
                            child: Icon(_showRhs2 ? Icons.close : Icons.add, color: Colors.white),
                          ),
                        ),
                        if (_showRhs2) ...[
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: _buildDropdown('RHS 2', _rhs2Rule, _rhsLabels.length - 1, (v) { _rhs2Rule = v!; _triggerRender(); }, customLabels: _rhsLabels)),
                        ]
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFF333333))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('POST-PROCESSING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
                          const SizedBox(height: 12),
                          _buildDropdown('TRANSFORMATION', ['NONE', 'ITERATE', 'C_SEQ', 'D_SEQ'].indexOf(_postType), 3, (v) { 
                            setState(() => _postType = ['NONE', 'ITERATE', 'C_SEQ', 'D_SEQ'][v!]); _triggerRender(); 
                          }, customLabels: ['Raw', 'Iterate a(n)', 'C(n) Congruence', 'D(n) Diagonal Sum']),
                          
                          if (_postType == 'ITERATE') ...[
                            const SizedBox(height: 8),
                            _buildNumInput('ITERATION DEPTH (k)', _iterK, (v) { _iterK = v; _triggerRender(); }),
                          ],

                          if (_postType == 'C_SEQ' || _postType == 'D_SEQ') ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildDropdown('LOCAL MAP', _postGridScaleIdx - 1, 3, (v) { setState(() => _postGridScaleIdx = v! + 1); _triggerRender(); }, customLabels: ['b', 'b²', 'b³', 'Custom'])),
                                if (_postGridScaleIdx == 4) ...[
                                  const SizedBox(width: 8),
                                  Expanded(child: _buildNumInput('ROWS', _customPostR, (v) { _customPostR = v; _triggerRender(); })),
                                  const SizedBox(width: 8),
                                  Expanded(child: _buildNumInput('COLS', _customPostC, (v) { _customPostC = v; _triggerRender(); })),
                                ]
                              ],
                            ),
                          ],
                          
                          if (_postType == 'C_SEQ') ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildNumInput('TARGET (T)', _targetT, (v) { _targetT = v; _triggerRender(); })),
                                const SizedBox(width: 8),
                                Expanded(child: _buildNumInput('MOD (Mc)', _modMc, (v) { _modMc = v; _triggerRender(); })),
                              ],
                            )
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFF333333))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('ANIMATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
                          const SizedBox(height: 12),
                          _buildDropdown('MODE', ['modeA', 'modeB', 'modeC'].indexOf(_animMode), 2, (v) { 
                            setState(() => _animMode = ['modeA', 'modeB', 'modeC'][v!]); 
                          }, customLabels: ['A: Vary Block', 'B: Vary Base', 'C: Vary Modulo']),
                          const SizedBox(height: 8),
                          
                          if (_animMode == 'modeA')
                            _buildNumInput('BLOCK OFFSET', _animPVal, (v) { setState(() => _animPVal = v); }),
                          
                          if (_animMode == 'modeB' || _animMode == 'modeC') ...[
                            Row(
                              children: [
                                Expanded(child: _buildNumInput('BLOCK (p)', _animPVal, (v) { setState(() => _animPVal = v); })),
                                const SizedBox(width: 8),
                                Expanded(child: _buildNumInput('START', _animStart, (v) { setState(() => _animStart = v); })),
                                const SizedBox(width: 8),
                                Expanded(child: _buildNumInput('END', _animEnd, (v) { setState(() => _animEnd = v); })),
                              ],
                            )
                          ]
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildNumInput('TUPLE DEPTH', _tupleK, (v) { _tupleK = v; _triggerRender(); })),
                        const SizedBox(width: 8),
                        Expanded(child: ElevatedButton.icon(
                          onPressed: _randomizeColors,
                          icon: const Icon(Icons.palette, size: 16),
                          label: const Text('COLOR'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2A2A2A)),
                        )),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : () => _exportArtifact(false),
                          icon: const Icon(Icons.download),
                          label: const Text('HI-RES PNG'),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondary),
                          onPressed: _is processing ? null : () => _exportArtifact(true),
                          icon: const Icon(Icons.animation),
                          label: const Text('BUILD GIF'),
                        )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Export uses GRID setting limits.', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, int currentVal, int maxVal, ValueChanged<int?> onChanged, {List<String>? customLabels}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          height: 48,
          decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: const Color(0xFF333333))),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButton<int>(
            isExpanded: true, underline: const SizedBox(),
            dropdownColor: const Color(0xFF1E1E1E),
            value: currentVal,
            items: List.generate(maxVal + 1, (i) => DropdownMenuItem(value: i, child: Text(customLabels != null ? customLabels[i] : 'Rule $i', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),
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
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: TextFormField(
            initialValue: val.toString(),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(contentPadding: EdgeInsets.zero),
            onFieldSubmitted: (str) {
              int? parsed = int.tryParse(str);
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
