import 'dart:io';
import 'dart:isolate';
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

// Isolate payload for large graphs (>80 nodes). Uses primitive doubles to avoid
// SendPort serialization cost of Offset objects. Falls back to main isolate
// for small graphs (overhead > benefit).
class _NodeInput {
  final int id;
  final double x, y, vx, vy;
  final bool pinned;
  const _NodeInput(this.id, this.x, this.y, this.vx, this.vy, this.pinned);
}

class _RelInput {
  final int from, to;
  const _RelInput(this.from, this.to);
}

class _PhysicsInput {
  final List<_NodeInput> nodes;
  final List<_RelInput> rels;
  final double repulsion, attraction, naturalLen, damping, centerGravity;
  const _PhysicsInput({
    required this.nodes,
    required this.rels,
    required this.repulsion,
    required this.attraction,
    required this.naturalLen,
    required this.damping,
    required this.centerGravity,
  });
}

class _NodeOutput {
  final int id;
  final double x, y, vx, vy;
  const _NodeOutput(this.id, this.x, this.y, this.vx, this.vy);
}

// Top-level so it can be sent to Isolate.run
List<_NodeOutput> _computePhysicsInIsolate(_PhysicsInput input) {
  final nodes = input.nodes;
  final rels = input.rels;
  // Copy mutable velocities/positions into maps for quick lookup
  final posX = <int, double>{for (final n in nodes) n.id: n.x};
  final posY = <int, double>{for (final n in nodes) n.id: n.y};
  final velX = <int, double>{for (final n in nodes) n.id: n.vx};
  final velY = <int, double>{for (final n in nodes) n.id: n.vy};
  final pinned = <int, bool>{for (final n in nodes) n.id: n.pinned};

  // Edge attraction
  for (final rel in rels) {
    final ax = posX[rel.from];
    final ay = posY[rel.from];
    final bx = posX[rel.to];
    final by = posY[rel.to];
    if (ax == null || ay == null || bx == null || by == null) continue;
    if (pinned[rel.from] == true && pinned[rel.to] == true) continue;
    final dx = bx - ax;
    final dy = by - ay;
    final dist = sqrt(dx * dx + dy * dy).clamp(1.0, double.infinity);
    final force = input.attraction * (dist - input.naturalLen);
    final ux = dx / dist;
    final uy = dy / dist;
    if (pinned[rel.from] != true) {
      velX[rel.from] = (velX[rel.from] ?? 0) + ux * force;
      velY[rel.from] = (velY[rel.from] ?? 0) + uy * force;
    }
    if (pinned[rel.to] != true) {
      velX[rel.to] = (velX[rel.to] ?? 0) - ux * force;
      velY[rel.to] = (velY[rel.to] ?? 0) - uy * force;
    }
  }

  // Node repulsion O(n²)
  for (int i = 0; i < nodes.length; i++) {
    for (int j = i + 1; j < nodes.length; j++) {
      final a = nodes[i];
      final b = nodes[j];
      final ax = posX[a.id]!;
      final ay = posY[a.id]!;
      final bx = posX[b.id]!;
      final by = posY[b.id]!;
      final dx = ax - bx;
      final dy = ay - by;
      final dist2 = dx * dx + dy * dy;
      final dist = dist2 < 1.0 ? 1.0 : sqrt(dist2);
      final force = input.repulsion / (dist * dist);
      final ux = dx / dist;
      final uy = dy / dist;
      if (!a.pinned) {
        velX[a.id] = (velX[a.id] ?? 0) + ux * force;
        velY[a.id] = (velY[a.id] ?? 0) + uy * force;
      }
      if (!b.pinned) {
        velX[b.id] = (velX[b.id] ?? 0) - ux * force;
        velY[b.id] = (velY[b.id] ?? 0) - uy * force;
      }
    }
  }

  // Center gravity + integrate + damping, return new state
  final out = <_NodeOutput>[];
  for (final n in nodes) {
    if (n.pinned) {
      out.add(_NodeOutput(n.id, n.x, n.y, n.vx, n.vy));
      continue;
    }
    double vx = velX[n.id] ?? 0;
    double vy = velY[n.id] ?? 0;
    vx -= n.x * input.centerGravity;
    vy -= n.y * input.centerGravity;
    vx *= input.damping;
    vy *= input.damping;
    final nx = n.x + vx;
    final ny = n.y + vy;
    out.add(_NodeOutput(n.id, nx, ny, vx, vy));
  }
  return out;
}

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

class _GraphScreenState extends State<GraphScreen> with TickerProviderStateMixin {
  final Map<int, _PhysNode> _nodes = {};
  final Map<int, bool> _fileExistsCache = {};
  final Map<int, ImageProvider> _avatarProviderCache = {};
  List<Relationship> _latestRels = [];
  int _paintVersion = 0;

  late Ticker _ticker;
  late AnimationController _centerController;
  final Random _rng = Random();
  int _frameCount = 0;
  int _idleFrames = 0;
  Size _lastGraphSize = Size.zero;
  bool _didInitOffset = false;
  bool _isComputingIsolate = false;

  // Pan + zoom
  Offset _canvasOffset = Offset.zero;
  double _scale = 1.0;
  Offset _focalPointStart = Offset.zero;
  Offset _canvasOffsetStart = Offset.zero;
  double _scaleStart = 1.0;

  int? _draggingId;
  Offset _dragLocalStart = Offset.zero;

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

  // Hoisted consts — avoid `withValues(alpha:)` allocation per frame
  static const Color _shadowColor = Color(0x1F000000); // 12%
  static const Color _shadowColorLight = Color(0x0F000000); // 6%
  static const Color _avatarBorder = Colors.white;
  static const BoxShadow _avatarShadow = BoxShadow(color: _shadowColor, blurRadius: 4, offset: Offset(0, 1));
  static const BoxShadow _labelShadow = BoxShadow(color: _shadowColorLight, blurRadius: 2, offset: Offset(0, 1));

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _centerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
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

  Future<void> _centerOnPerson(int personId) async {
    final node = _nodes[personId];
    if (node == null) return;
    Size size = _lastGraphSize;
    if (size.isEmpty || size.width == 0) {
      final mq = MediaQuery.maybeOf(context);
      if (mq != null) {
        size = Size(mq.size.width, mq.size.height - 56 - 84 - mq.padding.top - mq.padding.bottom);
      } else {
        return;
      }
    }
    final target = Offset(size.width / 2 - node.pos.dx * _scale, size.height / 2 - node.pos.dy * _scale);
    final start = _canvasOffset;
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
    final removed = _nodes.keys.where((id) => !ids.contains(id)).toList();
    for (final id in removed) {
      _nodes.remove(id);
      _fileExistsCache.remove(id);
      _avatarProviderCache.remove(id);
    }
    bool added = false;
    for (final p in persons) {
      final isAsset = p.imagePath.startsWith('assets/');
      if (!_fileExistsCache.containsKey(p.id)) {
        _fileExistsCache[p.id!] = !isAsset && p.imagePath.isNotEmpty && File(p.imagePath).existsSync();
      } else {
        final existingNode = _nodes[p.id];
        if (existingNode != null && existingNode.person.imagePath != p.imagePath) {
          _fileExistsCache[p.id!] = !isAsset && p.imagePath.isNotEmpty && File(p.imagePath).existsSync();
          _avatarProviderCache.remove(p.id);
        }
      }
      // Pre-cache provider once per data change, not per frame
      if (_fileExistsCache[p.id] == true && !_avatarProviderCache.containsKey(p.id)) {
        _avatarProviderCache[p.id!] = ResizeImage(FileImage(File(p.imagePath)), width: 140, height: 140);
      } else if (isAsset && !_avatarProviderCache.containsKey(p.id)) {
        _avatarProviderCache[p.id!] = AssetImage(p.imagePath);
      }

      if (!_nodes.containsKey(p.id)) {
        added = true;
        Offset pos;
        if (_pendingAddCanvasPos != null) {
          pos = _pendingAddCanvasPos! + Offset((_rng.nextDouble() - 0.5) * 20, (_rng.nextDouble() - 0.5) * 20);
          _pendingAddCanvasPos = null;
        } else {
          final angle = _rng.nextDouble() * 2 * pi;
          final r = 80.0 + _rng.nextDouble() * 140;
          pos = Offset(cos(angle) * r, sin(angle) * r);
        }
        _nodes[p.id!] = _PhysNode(p, pos);
      } else {
        final old = _nodes[p.id!]!;
        if (old.person != p) {
          _nodes[p.id!] = _PhysNode(p, old.pos)
            ..vel = old.vel
            ..pinned = old.pinned;
        }
      }
    }
    if (added) _ensureTickerRunning();
  }

  // Keep sync path for small graphs; async isolate for large graphs
  void _tick([Duration? _]) {
    if (!mounted || _isComputingIsolate) return;
    if (_nodes.isEmpty) {
      _idleFrames++;
      if (_idleFrames > 90 && _ticker.isActive) _ticker.stop();
      return;
    }
    _frameCount++;
    if (_frameCount % 2 != 0) return;

    // Large graph -> offload to isolate (threshold 80 nodes, O(n²) > 3200 pairs)
    if (_nodes.length > 80) {
      _tickIsolate();
      return;
    }

    // --- Main-isolate fast path ---
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

    final nodes = _nodes.values.toList(growable: false);
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        final delta = a.pos - b.pos;
        final dist2 = delta.distanceSquared;
        final dist = dist2 < 1.0 ? 1.0 : sqrt(dist2);
        final force = _repulsion / (dist * dist);
        final dir = delta / dist;
        if (!a.pinned) a.vel += dir * force;
        if (!b.pinned) b.vel -= dir * force;
      }
    }

    for (final n in nodes) {
      if (!n.pinned) n.vel -= n.pos * _centerGravity;
    }

    double maxVel = 0;
    for (final n in nodes) {
      if (n.pinned) continue;
      final d = n.vel.distance;
      if (d > maxVel) maxVel = d;
    }
    if (maxVel < 0.05 && _draggingId == null) {
      _idleFrames++;
      if (_idleFrames > 45 && _ticker.isActive) _ticker.stop();
      return;
    }
    _idleFrames = 0;
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

  Future<void> _tickIsolate() async {
    if (_isComputingIsolate) return;
    _isComputingIsolate = true;
    final nodeInputs = _nodes.values
        .map((n) => _NodeInput(n.person.id!, n.pos.dx, n.pos.dy, n.vel.dx, n.vel.dy, n.pinned))
        .toList(growable: false);
    final relInputs = _latestRels.map((r) => _RelInput(r.fromPersonId, r.toPersonId)).toList(growable: false);
    final input = _PhysicsInput(
      nodes: nodeInputs,
      rels: relInputs,
      repulsion: _repulsion,
      attraction: _attraction,
      naturalLen: _naturalLen,
      damping: _damping,
      centerGravity: _centerGravity,
    );
    try {
      final outputs = await Isolate.run(() => _computePhysicsInIsolate(input));
      if (!mounted) return;
      double maxVel = 0;
      for (final o in outputs) {
        final node = _nodes[o.id];
        if (node == null || node.pinned) continue;
        node.pos = Offset(o.x, o.y);
        node.vel = Offset(o.vx, o.vy);
        final d = node.vel.distance;
        if (d > maxVel) maxVel = d;
      }
      if (maxVel < 0.05 && _draggingId == null) {
        _idleFrames++;
        if (_idleFrames > 45 && _ticker.isActive) _ticker.stop();
      } else {
        _idleFrames = 0;
      }
      if (mounted) setState(() => _paintVersion++);
    } finally {
      _isComputingIsolate = false;
    }
  }

  Offset _toCanvas(Offset screen) => (screen - _canvasOffset) / _scale;
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isDesktop = constraints.maxWidth > 900;
          // Reusable graph column (used in both layouts)
          Widget graphColumn = Column(
            children: [
              Expanded(
                child: Selector<PersonProvider, _GraphData>(
                  selector: (_, p) => _GraphData(p.persons, p.relationships),
                  shouldRebuild: (a, b) =>
                      !identical(a.persons, b.persons) ||
                      !identical(a.relationships, b.relationships) ||
                      a.persons.length != b.persons.length ||
                      a.relationships.length != b.relationships.length,
                  builder: (context, data, _) {
                    final provider = context.read<PersonProvider>();
                    if (kDebugMode) {
                      debugPrint('GraphScreen build: persons=${data.persons.length} rels=${data.relationships.length} nodes=${_nodes.length}');
                    }
                    if (data.persons.isEmpty) {
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
                              style: TextStyle(color: Colors.black.withValues(alpha: 0.5), fontSize: 10),
                            ),
                          ),
                        ],
                      );
                    }
                    final needsSync = data.persons.any((p) => !_nodes.containsKey(p.id)) ||
                        _nodes.length != data.persons.length ||
                        data.persons.any((p) => _nodes[p.id]?.person != p);
                    if (needsSync) _syncNodes(data.persons);
                    _latestRels = data.relationships;
                    return Stack(
                      children: [
                        RepaintBoundary(child: _buildInteractiveGraph(provider, data.relationships)),
                        // On small screens show overlay badge; on desktop badge moves to sidebar
                        if (!isDesktop)
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
                                '${data.persons.length} persons • ${data.relationships.length} rels',
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
              // Bottom pale area scales with screen — fixed 84 on phone, smaller on desktop
              Container(height: isDesktop ? 48 : 84, width: double.infinity, color: AppColors.bgLight),
            ],
          );

          if (isDesktop) {
            // Large-screen layout: graph + sidebar (prevents stretching, uses Expanded/Flexible correctly)
            return Row(
              children: [
                Expanded(child: graphColumn),
                const VerticalDivider(width: 1, color: AppColors.vividRed),
                SizedBox(
                  width: 320,
                  child: Selector<PersonProvider, _GraphData>(
                      selector: (_, p) => _GraphData(p.persons, p.relationships),
                      builder: (_, data, _) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Overview',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2B0000), letterSpacing: 0.8)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.coral.withValues(alpha: 0.2))),
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${data.persons.length}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.vividRed)),
                                    const Text('persons', style: TextStyle(fontSize: 11, color: Colors.black54)),
                                  ])),
                                  Container(width: 1, height: 36, color: Colors.black12),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${data.relationships.length}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.coral)),
                                    const Text('relationships', style: TextStyle(fontSize: 11, color: Colors.black54)),
                                  ])),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('TIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54, letterSpacing: 0.8)),
                            const SizedBox(height: 6),
                            const Text('Drag nodes to reposition • Pinch to zoom • Tap empty space to add\nOn large screens graph and details sit side-by-side to avoid stretching.',
                                style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4)),
                            const Spacer(),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            const Text('Window size determines layout — not device type.\nResize window to see phone ↔ desktop transition (LayoutBuilder).',
                                style: TextStyle(fontSize: 10, color: Colors.black38, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }
          // Small-screen: default Column (phone)
          return graphColumn;
        },
      ),
    );
  }

  Widget _buildInteractiveGraph(PersonProvider provider, List<Relationship> rels) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastGraphSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (!_didInitOffset && _canvasOffset == Offset.zero && constraints.maxWidth > 0) {
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
            Future.delayed(const Duration(milliseconds: 150), () => _didDrag = false);
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
                if (_tapAddTime != null && DateTime.now().difference(_tapAddTime!).inSeconds >= 4) {
                  setState(() => _tapAddPos = null);
                }
              });
            }
          },
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: _EdgePainter(
                    nodes: _nodes,
                    relationships: rels,
                    canvasOffset: _canvasOffset,
                    scale: _scale,
                    nodeRadius: _nodeRadius,
                    version: _paintVersion,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              ..._nodes.values.map((node) {
                final center = _toScreen(node.pos);
                final r = _nodeRadius * _scale;
                final fileExists = _fileExistsCache[node.person.id] ?? false;
                final isAsset = node.person.imagePath.startsWith('assets/');
                Widget avatar;
                if (isAsset) {
                  avatar = CircleAvatar(
                    radius: r,
                    backgroundImage: _avatarProviderCache[node.person.id] ?? AssetImage(node.person.imagePath),
                    backgroundColor: Colors.white,
                    onBackgroundImageError: (_, _) {},
                  );
                } else if (fileExists) {
                  avatar = CircleAvatar(
                    radius: r,
                    backgroundImage: _avatarProviderCache[node.person.id]!,
                    backgroundColor: Colors.white,
                    onBackgroundImageError: (_, _) {},
                  );
                } else {
                  final initial = node.person.name.isNotEmpty ? node.person.name[0].toUpperCase() : '?';
                  avatar = CircleAvatar(
                    radius: r,
                    backgroundColor: Colors.white,
                    child: Text(initial, style: TextStyle(color: AppColors.vividRed, fontWeight: FontWeight.bold, fontSize: r * 0.7)),
                  );
                }
                return Positioned(
                  left: center.dx - r,
                  top: center.dy - r,
                  child: RepaintBoundary(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Reduced shadow blur: 4 instead of 6, cheaper raster
                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.fromBorderSide(BorderSide(color: _avatarBorder, width: 2)),
                            boxShadow: [_avatarShadow],
                          ),
                          child: avatar,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: const BoxDecoration(
                            color: Color(0xF2FFFFFF), // 95%
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            border: Border.fromBorderSide(BorderSide(color: Color(0x33FF655B))),
                            boxShadow: [_labelShadow],
                          ),
                          child: Text(
                            node.person.name.split(' ').first,
                            style: TextStyle(color: Colors.black87, fontSize: (10 * _scale).clamp(8.0, 11.0), fontWeight: FontWeight.w600),
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
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AddNodeWizardScreen()));
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.coral,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
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

// Lightweight view for Selector
class _GraphData {
  final List<Person> persons;
  final List<Relationship> relationships;
  const _GraphData(this.persons, this.relationships);
}

class _EdgePainter extends CustomPainter {
  final Map<int, _PhysNode> nodes;
  final List<Relationship> relationships;
  final Offset canvasOffset;
  final double scale;
  final double nodeRadius;
  final int version;

  // LRU-ish label cache: key = "label|mutual|bucket"
  static final Map<String, TextPainter> _labelCache = {};
  static const int _maxCache = 64;

  // Hoisted paints — no `withValues` per edge
  static const Color _mutualEdge = Color(0xE6FF1E25); // 90%
  static const Color _normalEdge = Color(0xBF000000); // 75%
  static const Color _bgWhite = Color(0xEBFFFFFF); // 92%
  static const Color _borderMutual = Color(0x33FF1E25);
  static const Color _borderNormal = Color(0x33000000);
  static final Paint _bgPaint = Paint()..color = _bgWhite;
  static final Paint _borderMutualPaint = Paint()
    ..color = _borderMutual
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  static final Paint _borderNormalPaint = Paint()
    ..color = _borderNormal
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  static final Paint _arrowMutual = Paint()
    ..color = AppColors.vividRed
    ..style = PaintingStyle.fill;
  static final Paint _arrowNormal = Paint()
    ..color = _normalEdge
    ..style = PaintingStyle.fill;
  static final Paint _mutualLinePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _normalLinePaint = Paint()..style = PaintingStyle.stroke;

  _EdgePainter({
    required this.nodes,
    required this.relationships,
    required this.canvasOffset,
    required this.scale,
    required this.nodeRadius,
    required this.version,
  });

  Offset _toScreen(Offset canvas) => canvas * scale + canvasOffset;

  TextPainter _cachedLabel(String label, bool mutual, double scale) {
    final bucket = (scale * 10).round(); // 0.1 granularity
    final key = '$label|$mutual|$bucket';
    final hit = _labelCache[key];
    if (hit != null) return hit;
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
    if (_labelCache.length >= _maxCache) _labelCache.remove(_labelCache.keys.first);
    _labelCache[key] = tp;
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final margin = 80 * scale;
    for (final rel in relationships) {
      final a = nodes[rel.fromPersonId];
      final b = nodes[rel.toPersonId];
      if (a == null || b == null) continue;
      final from = _toScreen(a.pos);
      final to = _toScreen(b.pos);
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
        final Paint linePaint = rel.isMutual ? _mutualLinePaint : _normalLinePaint;
        linePaint.color = rel.isMutual ? _mutualEdge : _normalEdge;
        linePaint.strokeWidth = (rel.isMutual ? 1.6 : 1.0) * scale;
        canvas.drawLine(lineFrom, lineTo, linePaint);
      }
      _drawArrow(canvas, from, to, rel.isMutual);
      _drawEdgeLabel(canvas, from, to, rel.label, rel.isMutual);
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
    final left = Offset(tip.dx - arrowLen * (unit.dx * cos(arrowAngle) - unit.dy * sin(arrowAngle)),
        tip.dy - arrowLen * (unit.dy * cos(arrowAngle) + unit.dx * sin(arrowAngle)));
    final right = Offset(tip.dx - arrowLen * (unit.dx * cos(-arrowAngle) - unit.dy * sin(-arrowAngle)),
        tip.dy - arrowLen * (unit.dy * cos(-arrowAngle) + unit.dx * sin(-arrowAngle)));
    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(arrowPath, mutual ? _arrowMutual : _arrowNormal);
    if (mutual) {
      final fromUnit = -unit;
      final fromTip = from - fromUnit * (-(nodeRadius * scale + 14));
      final fromLeft = Offset(fromTip.dx - arrowLen * (fromUnit.dx * cos(arrowAngle) - fromUnit.dy * sin(arrowAngle)),
          fromTip.dy - arrowLen * (fromUnit.dy * cos(arrowAngle) + fromUnit.dx * sin(arrowAngle)));
      final fromRight = Offset(fromTip.dx - arrowLen * (fromUnit.dx * cos(-arrowAngle) - fromUnit.dy * sin(-arrowAngle)),
          fromTip.dy - arrowLen * (fromUnit.dy * cos(-arrowAngle) + fromUnit.dx * sin(-arrowAngle)));
      final fromArrow = Path()
        ..moveTo(fromTip.dx, fromTip.dy)
        ..lineTo(fromLeft.dx, fromLeft.dy)
        ..lineTo(fromRight.dx, fromRight.dy)
        ..close();
      canvas.drawPath(fromArrow, _arrowMutual);
    }
  }

  void _drawEdgeLabel(Canvas canvas, Offset from, Offset to, String label, bool mutual) {
    if (label.isEmpty) return;
    final mid = (from + to) / 2;
    final tp = _cachedLabel(label, mutual, scale);
    final bgRect = Rect.fromCenter(center: mid, width: tp.width + 8, height: tp.height + 4);
    final rrect = RRect.fromRectAndRadius(bgRect, const Radius.circular(6));
    canvas.drawRRect(rrect, _bgPaint);
    canvas.drawRRect(rrect, mutual ? _borderMutualPaint : _borderNormalPaint);
    tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) {
    return version != old.version ||
        canvasOffset != old.canvasOffset ||
        scale != old.scale ||
        !identical(relationships, old.relationships) ||
        relationships.length != old.relationships.length;
  }
}
