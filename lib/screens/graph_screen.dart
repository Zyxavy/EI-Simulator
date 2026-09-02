import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../models/person.dart';
import '../models/relationship.dart';
import '../providers/person_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/profile_bottom_sheet.dart';
import '../widgets/search_bottom_sheet.dart';
import 'add_node_wizard_screen.dart';

class _PhysNode {
  final Person person;
  Offset pos;
  Offset vel = Offset.zero;
  bool pinned = false;

  _PhysNode(this.person, this.pos);
}

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen>
    with TickerProviderStateMixin {
  final Map<int, _PhysNode> _nodes = {};
  // Cache: personId -> file exists on disk (avoid existsSync per frame)
  final Map<int, bool> _fileExistsCache = {};
  // Keep latest relationships for physics tick without mutating during build
  List<Relationship> _latestRels = [];
  // Version incremented each tick that actually moves nodes — drives CustomPainter repaint
  int _paintVersion = 0;

  late Ticker _ticker;
  late AnimationController _centerController;
  final Random _rng = Random();
  int _frameCount = 0;
  int _idleFrames = 0;
  Size _lastGraphSize = Size.zero;
  bool _didInitOffset = false;

  // Pan + zoom state
  Offset _canvasOffset = Offset.zero;
  double _scale = 1.0;
  Offset _focalPointStart = Offset.zero;
  Offset _canvasOffsetStart = Offset.zero;
  double _scaleStart = 1.0;

  // Drag state
  int? _draggingId;
  Offset _dragLocalStart = Offset.zero;

  // Contextual add button (appears at tap location on empty canvas, per spec)
  Offset? _tapAddPos;
  DateTime? _tapAddTime;
  Offset? _pendingAddCanvasPos;
  bool _didDrag = false;

  static const double _nodeRadius = 34.0;
  static const double _repulsion = 8000.0;
  static const double _attraction = 0.04;
  static const double _naturalLen = 200.0;
  static const double _damping = 0.75;
  static const double _centerGravity = 0.002;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _centerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Initial size probe — no need to force a second rebuild, LayoutBuilder
    // will provide constraints on first frame.
  }

  @override
  void dispose() {
    _ticker.dispose();
    _centerController.dispose();
    super.dispose();
  }

  void _ensureTickerRunning() {
    if (!_ticker.isActive) {
      _idleFrames = 0;
      _ticker.start();
    }
  }

  /// Smoothly pans/zooms so [personId]'s node lands centered in the graph viewport.
  Future<void> _centerOnPerson(int personId) async {
    final node = _nodes[personId];
    if (node == null) return;
    // Use last measured graph size; fallback to screen size
    Size size = _lastGraphSize;
    if (size.isEmpty || size.width == 0) {
      final mq = MediaQuery.maybeOf(context);
      if (mq != null) {
        size = Size(
          mq.size.width,
          mq.size.height - 56 - 84 - mq.padding.top - mq.padding.bottom,
        );
      } else {
        return;
      }
    }
    final target = Offset(
      size.width / 2 - node.pos.dx * _scale,
      size.height / 2 - node.pos.dy * _scale,
    );
    final start = _canvasOffset;
    // Briefly highlight by pinning the node during animation
    node.pinned = true;
    final anim = Tween<Offset>(begin: start, end: target).animate(
      CurvedAnimation(parent: _centerController, curve: Curves.easeInOutCubic),
    );
    void listener() {
      if (mounted) setState(() => _canvasOffset = anim.value);
    }

    anim.addListener(listener);
    try {
      await _centerController.forward(from: 0);
    } finally {
      anim.removeListener(listener);
      node.pinned = false;
      if (mounted) setState(() {});
      _ensureTickerRunning();
    }
  }

  void _syncNodes(List<Person> persons) {
    final ids = persons.map((p) => p.id!).toSet();
    // Prune removed + clear their file cache
    final removed = _nodes.keys.where((id) => !ids.contains(id)).toList();
    for (final id in removed) {
      _nodes.remove(id);
      _fileExistsCache.remove(id);
    }
    bool added = false;
    for (final p in persons) {
      // Cache file existence once per data change, not per frame
      final isAsset = p.imagePath.startsWith('assets/');
      if (!_fileExistsCache.containsKey(p.id)) {
        _fileExistsCache[p.id!] =
            !isAsset && p.imagePath.isNotEmpty && File(p.imagePath).existsSync();
      } else {
        // Invalidate if path changed (person mutated)
        final existingNode = _nodes[p.id];
        if (existingNode != null && existingNode.person.imagePath != p.imagePath) {
          _fileExistsCache[p.id!] =
              !isAsset && p.imagePath.isNotEmpty && File(p.imagePath).existsSync();
        }
      }
      if (!_nodes.containsKey(p.id)) {
        added = true;
        Offset pos;
        if (_pendingAddCanvasPos != null) {
          pos = _pendingAddCanvasPos! +
              Offset(
                (_rng.nextDouble() - 0.5) * 20,
                (_rng.nextDouble() - 0.5) * 20,
              );
          _pendingAddCanvasPos = null;
        } else {
          final angle = _rng.nextDouble() * 2 * pi;
          final r = 80.0 + _rng.nextDouble() * 140;
          pos = Offset(cos(angle) * r, sin(angle) * r);
        }
        _nodes[p.id!] = _PhysNode(p, pos);
      } else {
        // Update person reference without losing physics state
        final old = _nodes[p.id!]!;
        // Only recreate wrapper if person data changed; preserve vel/pinned
        if (old.person != p) {
          _nodes[p.id!] = _PhysNode(p, old.pos)
            ..vel = old.vel
            ..pinned = old.pinned;
        }
      }
    }
    if (added) _ensureTickerRunning();
  }

  void _tick([Duration? _]) {
    if (!mounted) return;
    if (_nodes.isEmpty) {
      _idleFrames++;
      if (_idleFrames > 90 && _ticker.isActive) _ticker.stop();
      return;
    }

    _frameCount++;
    if (_frameCount % 2 != 0) return; // throttle to ~30fps for physics

    // Apply edge attraction inside tick (previously done in build, which caused
    // state mutation during build and double work per frame).
    for (final rel in _latestRels) {
      final a = _nodes[rel.fromPersonId];
      final b = _nodes[rel.toPersonId];
      if (a == null || b == null) continue;
      final delta = b.pos - a.pos;
      final dist = delta.distance.clamp(1.0, double.infinity);
      final force = _attraction * (dist - _naturalLen);
      final dir = delta / dist;
      if (!a.pinned) a.vel += dir * force;
      if (!b.pinned) b.vel -= dir * force;
    }

    // Repulsion O(n²) — avoid allocating List copy each tick if possible
    // _nodes.values is a view; converting to list once is still needed for indexed loop
    // but we reuse the list reference locally and avoid extra collections.
    final nodes = _nodes.values.toList(growable: false);
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        final delta = a.pos - b.pos;
        final dist2 = delta.distanceSquared;
        // Clamp dist implicitly via max(1, sqrt) but use distanceSquared for perf
        final dist = dist2 < 1.0 ? 1.0 : sqrt(dist2);
        final force = _repulsion / (dist * dist);
        final dir = delta / dist;
        if (!a.pinned) a.vel += dir * force;
        if (!b.pinned) b.vel -= dir * force;
      }
    }

    for (final n in nodes) {
      if (!n.pinned) {
        n.vel -= n.pos * _centerGravity;
      }
    }

    double maxVel = 0;
    for (final n in nodes) {
      if (n.pinned) continue;
      final d = n.vel.distance;
      if (d > maxVel) maxVel = d;
    }
    if (maxVel < 0.05 && _draggingId == null) {
      _idleFrames++;
      // Sleep ticker after ~1.5s idle to save battery and avoid constant rebuilds
      if (_idleFrames > 45 && _ticker.isActive) {
        _ticker.stop();
      }
      return;
    }
    _idleFrames = 0;

    // Apply damping + integrate — batched in single setState to avoid intermediate invalidations
    if (mounted) {
      setState(() {
        for (final n in nodes) {
          if (n.pinned) continue;
          n.vel *= _damping;
          n.pos += n.vel;
        }
        _paintVersion++;
      });
    }
  }

  Offset _toCanvas(Offset screen) {
    return (screen - _canvasOffset) / _scale;
  }

  Offset _toScreen(Offset canvas) => canvas * _scale + _canvasOffset;

  _PhysNode? _hitTest(Offset canvasPos) {
    const hitPadding = 8.0;
    for (final n in _nodes.values) {
      if ((n.pos - canvasPos).distance < _nodeRadius + hitPadding) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          backgroundColor: AppColors.bgLight,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Epstein Island Simulator',
                style: TextStyle(
                  color: AppColors.vividRed,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: AppColors.vividRed, size: 22),
              onPressed: () async {
                final selected = await showSearchBottomSheet(context);
                if (selected != null && context.mounted) {
                  await _centerOnPerson(selected.id!);
                  await Future.delayed(const Duration(milliseconds: 220));
                  if (!context.mounted) return;
                  showProfileBottomSheet(context, selected);
                }
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AppColors.vividRed),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<PersonProvider>(
              builder: (context, provider, _) {
                if (kDebugMode) {
                  debugPrint(
                    'GraphScreen build: persons=${provider.persons.length} rels=${provider.relationships.length} nodes=${_nodes.length}',
                  );
                }
                if (provider.persons.isEmpty) {
                  _latestRels = const [];
                  return Stack(
                    children: [
                      const Center(
                        child: Text(
                          'No one here yet.\nTap anywhere on the graph to add someone.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black38),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Text(
                          'Debug: 0 persons (DB empty or seeding failed)\nTry: adb shell pm clear com.example.situationship then rerun',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.5),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                final needsSync =
                    provider.persons.any((p) => !_nodes.containsKey(p.id)) ||
                        _nodes.length != provider.persons.length ||
                        provider.persons.any((p) => _nodes[p.id]?.person != p);
                if (needsSync) {
                  _syncNodes(provider.persons);
                }
                // Store latest rels for physics tick — assignment only, no velocity mutation here
                _latestRels = provider.relationships;

                return Stack(
                  children: [
                    RepaintBoundary(child: _buildInteractiveGraph(provider)),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.coral.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${provider.persons.length} persons • ${provider.relationships.length} rels',
                          style: const TextStyle(color: Colors.black54, fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(height: 1, color: AppColors.vividRed),
          Container(height: 84, width: double.infinity, color: AppColors.bgLight),
        ],
      ),
    );
  }

  Widget _buildInteractiveGraph(PersonProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastGraphSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (!_didInitOffset && _canvasOffset == Offset.zero && constraints.maxWidth > 0) {
          // One-time centering without triggering an extra rebuild loop.
          _canvasOffset = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
          _didInitOffset = true;
        }
        return GestureDetector(
          onScaleStart: (details) {
            _focalPointStart = details.localFocalPoint;
            _canvasOffsetStart = _canvasOffset;
            _scaleStart = _scale;
            _didDrag = false;
            _ensureTickerRunning();
            if (_tapAddPos != null) setState(() => _tapAddPos = null);

            final canvasPos = _toCanvas(details.localFocalPoint);
            final hit = _hitTest(canvasPos);
            if (hit != null) {
              _draggingId = hit.person.id;
              hit.pinned = true;
              _dragLocalStart = canvasPos - hit.pos;
            }
          },
          onScaleUpdate: (details) {
            if (_draggingId != null && details.pointerCount == 1) {
              final node = _nodes[_draggingId!];
              if (node != null) {
                final canvasPos = _toCanvas(details.localFocalPoint);
                _didDrag = true;
                setState(() {
                  node.pos = canvasPos - _dragLocalStart;
                  node.vel = Offset.zero;
                });
                _paintVersion++;
              }
            } else if (_draggingId == null) {
              if ((details.localFocalPoint - _focalPointStart).distance > 6) _didDrag = true;
              setState(() {
                _scale = (_scaleStart * details.scale).clamp(0.2, 3.0);
                _canvasOffset = _canvasOffsetStart + (details.localFocalPoint - _focalPointStart);
              });
            }
          },
          onScaleEnd: (_) {
            if (_draggingId != null) {
              _nodes[_draggingId!]?.pinned = false;
              _ensureTickerRunning();
            }
            Future.delayed(const Duration(milliseconds: 150), () {
              _didDrag = false;
            });
            _draggingId = null;
          },
          onTapUp: (details) {
            if (_didDrag) {
              _didDrag = false;
              return;
            }
            final canvasPos = _toCanvas(details.localPosition);
            final hit = _hitTest(canvasPos);
            if (hit != null) {
              setState(() => _tapAddPos = null);
              showProfileBottomSheet(context, hit.person);
            } else {
              final clamped = Offset(
                details.localPosition.dx.clamp(28.0, constraints.maxWidth - 28.0),
                details.localPosition.dy.clamp(28.0, constraints.maxHeight - 28.0),
              );
              setState(() {
                _tapAddPos = clamped;
                _tapAddTime = DateTime.now();
              });
              Future.delayed(const Duration(seconds: 4), () {
                if (!mounted) return;
                if (_tapAddTime != null &&
                    DateTime.now().difference(_tapAddTime!).inSeconds >= 4) {
                  setState(() => _tapAddPos = null);
                }
              });
            }
          },
          child: Stack(
            children: [
              // Edges behind nodes — isolated repaint
              RepaintBoundary(
                child: CustomPaint(
                  painter: _EdgePainter(
                    nodes: _nodes,
                    relationships: provider.relationships,
                    canvasOffset: _canvasOffset,
                    scale: _scale,
                    nodeRadius: _nodeRadius,
                    version: _paintVersion,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              // Nodes — each avatar isolated with RepaintBoundary to avoid full-stack repaint on decodes
              ..._nodes.values.map((node) {
                final center = _toScreen(node.pos);
                final r = _nodeRadius * _scale;
                final isAsset = node.person.imagePath.startsWith('assets/');
                final fileExists = _fileExistsCache[node.person.id] ?? false;

                Widget avatar;
                if (isAsset) {
                  avatar = CircleAvatar(
                    radius: r,
                    backgroundImage: AssetImage(node.person.imagePath),
                    backgroundColor: Colors.white,
                    onBackgroundImageError: (_, _) {},
                  );
                } else if (fileExists) {
                  // Use ResizeImage to decode at ~2x display size, not full file resolution.
                  final targetPx = (r * 2 * MediaQuery.devicePixelRatioOf(context)).round().clamp(48, 256);
                  avatar = CircleAvatar(
                    radius: r,
                    backgroundImage: ResizeImage(
                      FileImage(File(node.person.imagePath)),
                      width: targetPx,
                      height: targetPx,
                    ),
                    backgroundColor: Colors.white,
                    onBackgroundImageError: (_, _) {},
                  );
                } else {
                  final initial = node.person.name.isNotEmpty ? node.person.name[0].toUpperCase() : '?';
                  avatar = CircleAvatar(
                    radius: r,
                    backgroundColor: Colors.white,
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: AppColors.vividRed,
                        fontWeight: FontWeight.bold,
                        fontSize: r * 0.7,
                      ),
                    ),
                  );
                }

                return Positioned(
                  left: center.dx - r,
                  top: center.dy - r,
                  child: RepaintBoundary(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: avatar,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.coral.withValues(alpha: 0.2)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            node.person.name.split(' ').first,
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: (10 * _scale).clamp(8.0, 11.0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (_tapAddPos != null)
                Positioned(
                  left: _tapAddPos!.dx - 24,
                  top: _tapAddPos!.dy - 24,
                  child: Material(
                    elevation: 6,
                    shape: const CircleBorder(),
                    color: Colors.transparent,
                    child: GestureDetector(
                      onTap: () {
                        _pendingAddCanvasPos = _toCanvas(_tapAddPos!);
                        setState(() => _tapAddPos = null);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AddNodeWizardScreen()),
                        );
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.coral,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EdgePainter extends CustomPainter {
  final Map<int, _PhysNode> nodes;
  final List<Relationship> relationships;
  final Offset canvasOffset;
  final double scale;
  final double nodeRadius;
  final int version;

  _EdgePainter({
    required this.nodes,
    required this.relationships,
    required this.canvasOffset,
    required this.scale,
    required this.nodeRadius,
    required this.version,
  });

  Offset _toScreen(Offset canvas) => canvas * scale + canvasOffset;

  @override
  void paint(Canvas canvas, Size size) {
    // Cheap culling: skip edges fully offscreen (expanded by label bg + arrow)
    final margin = 80 * scale;

    // Reuse paints — avoid allocating per edge per frame
    final bgPaint = Paint()..color = Colors.white.withValues(alpha: 0.92);
    final bgBorderMutual = Paint()
      ..color = AppColors.vividRed.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final bgBorderNormal = Paint()
      ..color = Colors.black12.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final rel in relationships) {
      final a = nodes[rel.fromPersonId];
      final b = nodes[rel.toPersonId];
      if (a == null || b == null) continue;

      final from = _toScreen(a.pos);
      final to = _toScreen(b.pos);

      // Frustum cull: if both endpoints offscreen on same side, skip paint + label
      if ((from.dx < -margin && to.dx < -margin) ||
          (from.dx > size.width + margin && to.dx > size.width + margin) ||
          (from.dy < -margin && to.dy < -margin) ||
          (from.dy > size.height + margin && to.dy > size.height + margin)) {
        continue;
      }

      final dirVec = to - from;
      final len = dirVec.distance;
      if (len < 1) continue;
      final dirUnit = dirVec / len;
      final edgeGap = nodeRadius * scale + 14;
      final lineFrom = from + dirUnit * edgeGap;
      final lineTo = to - dirUnit * edgeGap;

      if ((lineTo - lineFrom).distance >= 1) {
        final edgePaint = Paint()
          ..color = rel.isMutual
              ? AppColors.vividRed.withValues(alpha: 0.9)
              : Colors.black.withValues(alpha: 0.75)
          ..strokeWidth = (rel.isMutual ? 1.6 : 1.0) * scale
          ..style = PaintingStyle.stroke;
        canvas.drawLine(lineFrom, lineTo, edgePaint);
      }
      _drawArrow(canvas, from, to, rel.isMutual);
      _drawEdgeLabel(canvas, from, to, rel.label, rel.isMutual, bgPaint,
          rel.isMutual ? bgBorderMutual : bgBorderNormal);
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, bool mutual) {
    final dir = to - from;
    final len = dir.distance;
    if (len < 1) return;
    final unit = dir / len;
    final tipOffset = nodeRadius * scale + 14;
    final tip = to - unit * tipOffset;

    const arrowLen = 7.0;
    const arrowAngle = 0.5;
    final left = Offset(
      tip.dx - arrowLen * (unit.dx * cos(arrowAngle) - unit.dy * sin(arrowAngle)),
      tip.dy - arrowLen * (unit.dy * cos(arrowAngle) + unit.dx * sin(arrowAngle)),
    );
    final right = Offset(
      tip.dx - arrowLen * (unit.dx * cos(-arrowAngle) - unit.dy * sin(-arrowAngle)),
      tip.dy - arrowLen * (unit.dy * cos(-arrowAngle) + unit.dx * sin(-arrowAngle)),
    );

    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = mutual ? AppColors.vividRed : Colors.black.withValues(alpha: 0.75)
        ..style = PaintingStyle.fill,
    );

    if (mutual) {
      final fromUnit = -unit;
      final fromTip = from - fromUnit * (-(nodeRadius * scale + 14));
      final fromLeft = Offset(
        fromTip.dx -
            arrowLen * (fromUnit.dx * cos(arrowAngle) - fromUnit.dy * sin(arrowAngle)),
        fromTip.dy -
            arrowLen * (fromUnit.dy * cos(arrowAngle) + fromUnit.dx * sin(arrowAngle)),
      );
      final fromRight = Offset(
        fromTip.dx -
            arrowLen * (fromUnit.dx * cos(-arrowAngle) - fromUnit.dy * sin(-arrowAngle)),
        fromTip.dy -
            arrowLen * (fromUnit.dy * cos(-arrowAngle) + fromUnit.dx * sin(-arrowAngle)),
      );
      final fromArrow = Path()
        ..moveTo(fromTip.dx, fromTip.dy)
        ..lineTo(fromLeft.dx, fromLeft.dy)
        ..lineTo(fromRight.dx, fromRight.dy)
        ..close();
      canvas.drawPath(
        fromArrow,
        Paint()
          ..color = AppColors.vividRed
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawEdgeLabel(
    Canvas canvas,
    Offset from,
    Offset to,
    String label,
    bool mutual,
    Paint bg,
    Paint border,
  ) {
    if (label.isEmpty) return;
    final mid = (from + to) / 2;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: mutual ? AppColors.vividRed : Colors.black87,
          fontSize: (9 * scale).clamp(7.0, 10.0),
          fontStyle: FontStyle.italic,
          fontWeight: mutual ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bgRect = Rect.fromCenter(center: mid, width: tp.width + 8, height: tp.height + 4);
    final rrect = RRect.fromRectAndRadius(bgRect, const Radius.circular(6));
    canvas.drawRRect(rrect, bg);
    canvas.drawRRect(rrect, border);
    tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) {
    // Version bump on every physics move ensures repaint only when needed;
    // also repaint on pan/zoom or relationship change.
    return version != old.version ||
        canvasOffset != old.canvasOffset ||
        scale != old.scale ||
        !identical(relationships, old.relationships) ||
        relationships.length != old.relationships.length;
  }
}
