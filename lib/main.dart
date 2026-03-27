import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'engine.dart';
import 'native_backend.dart';

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

class ExportWorkerRequest {
  final ExportConfig exportConfig;
  final String outputPath;
  final bool useNativePng;

  const ExportWorkerRequest({
    required this.exportConfig,
    required this.outputPath,
    required this.useNativePng,
  });
}

class ExportWorkerDone {
  final String path;
  final bool isGif;
  const ExportWorkerDone(this.path, this.isGif);
}

class ExportWorkerError {
  final String error;
  const ExportWorkerError(this.error);
}

void exportWorkerMain(List<dynamic> args) async {
  final SendPort sendPort = args[0] as SendPort;
  final ExportWorkerRequest req = args[1] as ExportWorkerRequest;

  try {
    final outFile = File(req.outputPath);
    if (await outFile.exists()) {
      await outFile.delete();
    }
    await outFile.create(recursive: true);

    if (req.useNativePng) {
      nativeExportPngTask(
        NativeFileTaskArgs(req.exportConfig.engine, req.outputPath),
      );
    } else {
      final bytes = await backgroundExportTask(req.exportConfig);
      await outFile.writeAsBytes(bytes, flush: true);
    }

    sendPort.send(ExportWorkerDone(req.outputPath, req.exportConfig.isGif));
  } catch (e) {
    sendPort.send(ExportWorkerError(e.toString()));
  }
}

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
  String _backendLabel = 'dart';

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
    _currentPalette = buildPaletteData(safeMod(_modM), _hueShift);
  }

  void _randomizeColors() {
    _hueShift = math.Random().nextDouble() * 360.0;
    _generatePalette();
    _debouncedRender();
  }

  int _getDim(int scaleIdx, int customDim) {
    final b = safeBase(_bNum);
    if (scaleIdx == 4) return math.max(1, customDim);
    return math.pow(b, scaleIdx).toInt();
  }

  int _getPreviewDim(int logicalDim) => math.min(logicalDim, devicePreviewCap());

  void _debouncedRender() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 180), _triggerRender);
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

  EngineConfig _buildEngineConfig({
    required int logicalDim,
    required int renderDim,
    required int renderId,
  }) {
    final postR = _getDim(_postGridScaleIdx, _customPostR);
    final postC = _getDim(_postGridScaleIdx, _customPostC);

    return EngineConfig(
      startN: BigInt.from(_pVal * logicalDim * logicalDim),
      bNum: safeBase(_bNum),
      renderR: renderDim,
      renderC: renderDim,
      logicalR: logicalDim,
      logicalC: logicalDim,
      modM: safeMod(_modM),
      lhsRule: _lhsRule,
      rhs1Rule: _rhs1Rule,
      rhs2Rule: _rhs2Rule,
      logicOp: _logicOp,
      postType: _postType,
      iterK: math.max(1, _iterK),
      postGridR: math.max(1, postR),
      postGridC: math.max(1, postC),
      targetT: _targetT,
      modMc: safeMod(_modMc),
      tupleK: safeTupleK(_tupleK),
      palette: _currentPalette,
      hueShift: _hueShift,
      renderId: renderId,
    );
  }

  Future<void> _triggerRender() async {
    final logicalDim = _getDim(_viewScaleIdx, _customViewDim);
    final previewDim = _getPreviewDim(logicalDim);
    final renderId = ++_activeRenderId;

    final cfg = _buildEngineConfig(
      logicalDim: logicalDim,
      renderDim: previewDim,
      renderId: renderId,
    );

    _renderReceivePort?.close();
    _renderIsolate?.kill(priority: Isolate.immediate);

    _previewPixels = Uint8List(previewDim * previewDim * 4);
    _previewW = previewDim;
    _previewH = previewDim;

    final useNative = canUseNativeForConfig(cfg);
    _backendLabel = useNative ? 'native' : 'dart';

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

    _renderIsolate = await Isolate.spawn(
      useNative ? liveNativePreviewIsolate : liveRenderIsolate,
      [rp.sendPort, cfg],
    );
  }

  Future<Directory> _getExportDirectory() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory('${ext.path}/exports');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      }
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void _offerShare(String path, bool asGif) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved: $path'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'SHARE',
          onPressed: () async {
            await Share.shareXFiles(
              [XFile(path, mimeType: asGif ? 'image/gif' : 'image/png')],
              text: 'Universal Sequence Render',
            );
          },
        ),
      ),
    );
  }

  Future<void> _exportArtifact(bool asGif) async {
    setState(() {
      _isProcessing = true;
      _renderProgress = 0.0;
    });

    try {
      final dim = _getDim(_viewScaleIdx, _customViewDim);
      final cfg = _buildEngineConfig(
        logicalDim: dim,
        renderDim: dim,
        renderId: 0,
      );

      final useNativePng = !asGif && canUseNativeForConfig(cfg);

      if (asGif && dim > 1024) {
        throw Exception('GIF export is safety-capped at 1024. Lower resolution.');
      }

      if (!asGif && !useNativePng && dim > 4096) {
        throw Exception(
          'This PNG mode is too large for safe fallback export. Use raw mode (post NONE) on Android for native PNG export, or lower resolution.',
        );
      }

      int frames = 1;
      if (asGif) {
        if (_animMode == 'modeA') {
          frames = safeBase(_bNum);
        } else if (_animMode == 'modeB' || _animMode == 'modeC') {
          frames = math.max(1, (_animEnd - _animStart) + 1);
        }
      }

      final exportCfg = ExportConfig(
        engine: cfg,
        isGif: asGif,
        frames: frames,
        animMode: _animMode,
        animStart: _animStart,
        animEnd: _animEnd,
        animPVal: _animPVal,
      );

      final exportDir = await _getExportDirectory();
      final ext = asGif ? 'gif' : 'png';
      final filePath =
          '${exportDir.path}/SEQ_b${safeBase(_bNum)}_m${safeMod(_modM)}_${dim}x$dim.$ext';

      final rp = ReceivePort();
      final completer = Completer<ExportWorkerDone>();
      Isolate? worker;

      rp.listen((message) {
        if (message is ExportWorkerDone) {
          if (!completer.isCompleted) completer.complete(message);
          rp.close();
          worker?.kill(priority: Isolate.immediate);
        } else if (message is ExportWorkerError) {
          if (!completer.isCompleted) {
            completer.completeError(message.error);
          }
          rp.close();
          worker?.kill(priority: Isolate.immediate);
        }
      });

      worker = await Isolate.spawn(
        exportWorkerMain,
        [
          rp.sendPort,
          ExportWorkerRequest(
            exportConfig: exportCfg,
            outputPath: filePath,
            useNativePng: useNativePng,
          ),
        ],
      );

      final result = await completer.future;

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _renderProgress = 1.0;
      });

      _offerShare(result.path, asGif);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
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
                        'b:${safeBase(_bNum)} | m:${safeMod(_modM)} | grid:$logicalDim | preview:$previewDim | $_backendLabel',
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
                      _buildNumInput('CUSTOM RESOLUTION', _customViewDim, (v) {
                        _customViewDim = v;
                        _debouncedRender();
                      }),
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
                            label: const Text('SAVE PNG'),
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
                            label: const Text('SAVE GIF'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (Platform.isAndroid)
                      Text(
                        nativeBackendAvailable()
                            ? 'Android native backend detected.'
                            : 'Android native backend not loaded. Falling back to Dart.',
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                        textAlign: TextAlign.center,
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
