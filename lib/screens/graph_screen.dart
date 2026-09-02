import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/person_provider.dart';
import '../models/person.dart';
import '../models/relationship.dart';
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
  late AnimationController _ticker;
  late AnimationController _centerController;
  final Random _rng = Random();
  int _frameCount = 0;
  Size _lastGraphSize = Size.zero;

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

  static const double _nodeRadius = 34.0;
  static const double _repulsion = 8000.0;
  static const double _attraction = 0.04;
  static const double _naturalLen = 200.0;
  static const double _damping = 0.75;
  static const double _centerGravity = 0.002;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..addListener(_tick);
    _ticker.forward();
    _centerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _centerController.dispose();
    super.dispose();
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
        size = Size(mq.size.width, mq.size.height - 56 - 84 - mq.padding.top - mq.padding.bottom);
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
    _centerController.forward(from: 0);
    await _centerController.forward(from: 0);
    anim.removeListener(listener);
    node.pinned = false;
  }

  void _syncNodes(List<Person> persons) {
    final ids = persons.map((p) => p.id!).toSet();
    _nodes.removeWhere((id, _) => !ids.contains(id));
    for (final p in persons) {
      if (!_nodes.containsKey(p.id)) {
        final angle = _rng.nextDouble() * 2 * pi;
        final r = 80.0 + _rng.nextDouble() * 140;
        _nodes[p.id!] = _PhysNode(p, Offset(cos(angle) * r, sin(angle) * r));
      } else {
        _nodes[p.id!] = _PhysNode(p, _nodes[p.id!]!.pos)
          ..vel = _nodes[p.id!]!.vel
          ..pinned = _nodes[p.id!]!.pinned;
      }
    }
  }

  void _tick() {
    if (!mounted) return;
    final nodes = _nodes.values.toList();
    if (nodes.isEmpty) return;

    _frameCount++;
    if (_frameCount % 2 != 0) return;

    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        final delta = a.pos - b.pos;
        final dist = delta.distance.clamp(1.0, double.infinity);
        final force = (_repulsion / (dist * dist));
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
      maxVel = maxVel > n.vel.distance ? maxVel : n.vel.distance;
    }
    if (maxVel < 0.05 && _draggingId == null) return;

    if (mounted) {
      setState(() {
        for (final n in nodes) {
          if (n.pinned) continue;
          n.vel *= _damping;
          n.pos += n.vel;
        }
      });
    }
  }

  void _applyEdgeForces(List<Relationship> rels) {
    for (final rel in rels) {
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
  }

  Offset _toCanvas(Offset screen) {
    return (screen - _canvasOffset) / _scale;
  }

  Offset _toScreen(Offset canvas) => canvas * _scale + _canvasOffset;

  _PhysNode? _hitTest(Offset canvasPos) {
    for (final n in _nodes.values) {
      if ((n.pos - canvasPos).distance < _nodeRadius) return n;
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
                  // 1) sheet already popped via Navigator.pop(result)
                  // 2) center node's viewport with smooth pan
                  await _centerOnPerson(selected.id!);
                  // 3) brief pause for user to register centering
                  await Future.delayed(const Duration(milliseconds: 220));
                  if (!context.mounted) return;
                  // 4) present profile as bottom sheet - full flow
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
                debugPrint('GraphScreen build: persons=${provider.persons.length} rels=${provider.relationships.length} nodes=${_nodes.length}');
                if (provider.persons.isEmpty) {
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
                          'Debug: 0 persons (DB empty or seeding failed)\nTry: adb shell pm clear com.example.ei_simulator then rerun',
                          style: TextStyle(color: Colors.black.withValues(alpha: 0.5), fontSize: 10),
                        ),
                      ),
                    ],
                  );
                }

                final needsSync = provider.persons.any((p) => !_nodes.containsKey(p.id)) ||
                    _nodes.length != provider.persons.length;
                if (needsSync) {
                  _syncNodes(provider.persons);
                }
                _applyEdgeForces(provider.relationships);

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
          // Bottom red divider like mock
          Container(height: 1, color: AppColors.vividRed),
          // Bottom pale area (30% like mock) - keeps layout proportions
          Container(
            height: 84,
            width: double.infinity,
            color: AppColors.bgLight,
          ),
        ],
      ),

    );
  }

  Widget _buildInteractiveGraph(PersonProvider provider) {
    return LayoutBuilder(builder: (context, constraints) {
      // Capture size for centering animation
      _lastGraphSize = Size(constraints.maxWidth, constraints.maxHeight);
      if (_canvasOffset == Offset.zero && constraints.maxWidth > 0) {
        _canvasOffset = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
      }
      return GestureDetector(
        onScaleStart: (details) {
          _focalPointStart = details.focalPoint;
          _canvasOffsetStart = _canvasOffset;
          _scaleStart = _scale;
          // Any pan/zoom or drag hides contextual add button
          if (_tapAddPos != null) setState(() => _tapAddPos = null);

          final canvasPos = _toCanvas(details.focalPoint);
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
              final canvasPos = _toCanvas(details.focalPoint);
              setState(() {
                node.pos = canvasPos - _dragLocalStart;
                node.vel = Offset.zero;
              });
            }
          } else if (_draggingId == null) {
            setState(() {
              _scale = (_scaleStart * details.scale).clamp(0.2, 3.0);
              _canvasOffset = _canvasOffsetStart + (details.focalPoint - _focalPointStart);
            });
          }
        },
        onScaleEnd: (_) {
          if (_draggingId != null) {
            _nodes[_draggingId!]?.pinned = false;
          }
          _draggingId = null;
        },
        onTapUp: (details) {
          final canvasPos = _toCanvas(details.localPosition);
          final hit = _hitTest(canvasPos);
          if (hit != null) {
            setState(() => _tapAddPos = null);
            showProfileBottomSheet(context, hit.person);
          } else {
            // Tapped empty space (or near nodes) -> show contextual add button at tap location
            // Clamp to graph bounds with 28px inset for FAB
            final clamped = Offset(
              details.localPosition.dx.clamp(28.0, constraints.maxWidth - 28.0),
              details.localPosition.dy.clamp(28.0, constraints.maxHeight - 28.0),
            );
            setState(() {
              _tapAddPos = clamped;
              _tapAddTime = DateTime.now();
            });
            // Auto-hide after 4s
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
            // Dismiss add button when tapping empty again elsewhere: handled by onTapUp outside
            // Edges behind nodes
            CustomPaint(
              painter: _EdgePainter(
                nodes: _nodes,
                relationships: provider.relationships,
                canvasOffset: _canvasOffset,
                scale: _scale,
                nodeRadius: _nodeRadius,
              ),
              child: const SizedBox.expand(),
            ),
            // Nodes as widgets (avatar images + tags) on top of edges
            ..._nodes.values.map((node) {
              final center = _toScreen(node.pos);
              final r = _nodeRadius * _scale;
              final isAsset = node.person.imagePath.startsWith('assets/');
              final fileExists = !isAsset && File(node.person.imagePath).existsSync();

              Widget avatar;
              if (isAsset) {
                avatar = CircleAvatar(
                  radius: r,
                  backgroundImage: AssetImage(node.person.imagePath),
                  backgroundColor: Colors.white,
                  onBackgroundImageError: (_, _) {},
                );
              } else if (fileExists) {
                avatar = CircleAvatar(
                  radius: r,
                  backgroundImage: FileImage(File(node.person.imagePath)),
                  backgroundColor: Colors.white,
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

              // Keep tags: name below avatar (and optional personality chip)
              final firstTag = node.person.personality.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList().isNotEmpty
                  ? node.person.personality.split(',').first.trim()
                  : '';

              return Positioned(
                left: center.dx - r,
                top: center.dy - r,
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
                    if (firstTag.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.coral.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          firstTag,
                          style: TextStyle(
                            color: AppColors.vividRed,
                            fontSize: (7 * _scale).clamp(6.0, 8.0),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            // Contextual add button at tap location (empty space tap)
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
                      setState(() => _tapAddPos = null);
                      // Open wizard; position hint could be stored for future node placement
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
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ),
            // Tap to dismiss hint for contextual add
            if (_tapAddPos != null)
              Positioned(
                left: _tapAddPos!.dx - 40,
                top: _tapAddPos!.dy + 28,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                    child: const Text('Tap + to add node here', style: TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _EdgePainter extends CustomPainter {
  final Map<int, _PhysNode> nodes;
  final List<Relationship> relationships;
  final Offset canvasOffset;
  final double scale;
  final double nodeRadius;

  _EdgePainter({
    required this.nodes,
    required this.relationships,
    required this.canvasOffset,
    required this.scale,
    required this.nodeRadius,
  });

  Offset _toScreen(Offset canvas) => canvas * scale + canvasOffset;

  @override
  void paint(Canvas canvas, Size size) {
    for (final rel in relationships) {
      final a = nodes[rel.fromPersonId];
      final b = nodes[rel.toPersonId];
      if (a == null || b == null) continue;

      final from = _toScreen(a.pos);
      final to = _toScreen(b.pos);

      // Mock: thin black line, vivid red if mutual
      final edgePaint = Paint()
        ..color = rel.isMutual ? AppColors.vividRed.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.75)
        ..strokeWidth = rel.isMutual ? 1.6 * scale : 1.0 * scale
        ..style = PaintingStyle.stroke;

      canvas.drawLine(from, to, edgePaint);

      _drawArrow(canvas, from, to, rel.isMutual);

      _drawEdgeLabel(canvas, from, to, rel.label, rel.isMutual);
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, bool mutual) {
    final dir = (to - from);
    final len = dir.distance;
    if (len < 1) return;
    final unit = dir / len;
    final tipOffset = nodeRadius * scale + 6;
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
      final fromTip = from - fromUnit * (-(nodeRadius * scale + 6));
      final fromLeft = Offset(
        fromTip.dx - arrowLen * (fromUnit.dx * cos(arrowAngle) - fromUnit.dy * sin(arrowAngle)),
        fromTip.dy - arrowLen * (fromUnit.dy * cos(arrowAngle) + fromUnit.dx * sin(arrowAngle)),
      );
      final fromRight = Offset(
        fromTip.dx - arrowLen * (fromUnit.dx * cos(-arrowAngle) - fromUnit.dy * sin(-arrowAngle)),
        fromTip.dy - arrowLen * (fromUnit.dy * cos(-arrowAngle) + fromUnit.dx * sin(-arrowAngle)),
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

  void _drawEdgeLabel(Canvas canvas, Offset from, Offset to, String label, bool mutual) {
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
    final bgRect = Rect.fromCenter(
      center: mid,
      width: tp.width + 8,
      height: tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    // subtle border
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
      Paint()
        ..color = (mutual ? AppColors.vividRed : Colors.black12).withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}
