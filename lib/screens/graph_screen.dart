import 'dart:io' show File;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/person_provider.dart';
import '../models/person.dart';
import '../models/relationship.dart';
import 'profile_screen.dart';
import 'add_edit_person_screen.dart';
import 'search_screen.dart';

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
    with SingleTickerProviderStateMixin {
  final Map<int, _PhysNode> _nodes = {};
  late AnimationController _ticker;
  final Random _rng = Random();

  // Pan + zoom state
  Offset _canvasOffset = Offset.zero;
  double _scale = 1.0;
  Offset _focalPointStart = Offset.zero;
  Offset _canvasOffsetStart = Offset.zero;
  double _scaleStart = 1.0;

  // Drag state
  int? _draggingId;
  Offset _dragLocalStart = Offset.zero;

  // Tap detection
  Offset? _pointerDownPos;

  static const double _nodeRadius = 32.0;
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
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncNodes(List<Person> persons) {
    final ids = persons.map((p) => p.id!).toSet();
    // Remove stale
    _nodes.removeWhere((id, _) => !ids.contains(id));
    // Add new
    for (final p in persons) {
      if (!_nodes.containsKey(p.id)) {
        final angle = _rng.nextDouble() * 2 * pi;
        final r = 80.0 + _rng.nextDouble() * 140;
        _nodes[p.id!] = _PhysNode(p, Offset(cos(angle) * r, sin(angle) * r));
      } else {
        // Update person data in case it changed
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

    // Repulsion between all pairs
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

    // Center gravity
    for (final n in nodes) {
      if (!n.pinned) {
        n.vel -= n.pos * _centerGravity;
      }
    }

    setState(() {
      for (final n in nodes) {
        if (n.pinned) continue;
        n.vel *= _damping;
        n.pos += n.vel;
      }
    });
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

  // Convert screen coords to canvas coords
  Offset _toCanvas(Offset screen) {
    return (screen - _canvasOffset) / _scale;
  }

  _PhysNode? _hitTest(Offset canvasPos) {
    for (final n in _nodes.values) {
      if ((n.pos - canvasPos).distance < _nodeRadius) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('EI Simulator', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<PersonProvider>(
        builder: (context, provider, _) {
          if (provider.persons.isEmpty) {
            return const Center(
              child: Text(
                'No one here yet.\nAdd someone with the + button.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38),
              ),
            );
          }

          _syncNodes(provider.persons);
          _applyEdgeForces(provider.relationships);

          return _buildInteractiveGraph(provider);
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.pinkAccent,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEditPersonScreen()),
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildInteractiveGraph(PersonProvider provider) {
    return GestureDetector(
      onScaleStart: (details) {
        _focalPointStart = details.focalPoint;
        _canvasOffsetStart = _canvasOffset;
        _scaleStart = _scale;

        // Try to start a node drag
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
          // Drag node
          final node = _nodes[_draggingId!];
          if (node != null) {
            final canvasPos = _toCanvas(details.focalPoint);
            setState(() {
              node.pos = canvasPos - _dragLocalStart;
              node.vel = Offset.zero;
            });
          }
        } else if (_draggingId == null) {
          // Pan + zoom canvas
          setState(() {
            _scale = (_scaleStart * details.scale).clamp(0.2, 3.0);
            _canvasOffset = _canvasOffsetStart +
                (details.focalPoint - _focalPointStart);
          });
        }
      },
      onScaleEnd: (_) {
        if (_draggingId != null) {
          _nodes[_draggingId!]?.pinned = false;
        }
        _draggingId = null;
      },
      // Tap detection via pointer down/up
      onTapUp: (details) {
        final canvasPos = _toCanvas(details.localPosition);
        final hit = _hitTest(canvasPos);
        if (hit != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(person: hit.person),
            ),
          );
        }
      },
      child: CustomPaint(
        painter: _GraphPainter(
          nodes: _nodes,
          relationships: provider.relationships,
          canvasOffset: _canvasOffset,
          scale: _scale,
          nodeRadius: _nodeRadius,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final Map<int, _PhysNode> nodes;
  final List<Relationship> relationships;
  final Offset canvasOffset;
  final double scale;
  final double nodeRadius;

  _GraphPainter({
    required this.nodes,
    required this.relationships,
    required this.canvasOffset,
    required this.scale,
    required this.nodeRadius,
  });

  Offset _toScreen(Offset canvas) => canvas * scale + canvasOffset;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw edges
    for (final rel in relationships) {
      final a = nodes[rel.fromPersonId];
      final b = nodes[rel.toPersonId];
      if (a == null || b == null) continue;

      final from = _toScreen(a.pos);
      final to = _toScreen(b.pos);

      final edgePaint = Paint()
        ..color = rel.isMutual
            ? Colors.pinkAccent.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = rel.isMutual ? 2.5 * scale : 1.5 * scale
        ..style = PaintingStyle.stroke;

      canvas.drawLine(from, to, edgePaint);

      // Arrow tip
      _drawArrow(canvas, from, to, rel.isMutual, edgePaint);

      // Label
      _drawEdgeLabel(canvas, from, to, rel.label, rel.isMutual);
    }

    // Draw nodes (circles with avatar placeholder)
    for (final node in nodes.values) {
      final center = _toScreen(node.pos);
      final r = nodeRadius * scale;

      // Outer glow for mutual nodes
      final glowPaint = Paint()
        ..color = Colors.pinkAccent.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

      // Background circle
      final bgPaint = Paint()
        ..color = const Color(0xFF1A1A2E)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, r + 2, glowPaint);
      canvas.drawCircle(center, r, bgPaint);

      // Border
      final borderPaint = Paint()
        ..color = Colors.pinkAccent.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, r, borderPaint);

      // Initial letter
      final initial = node.person.name.isNotEmpty
          ? node.person.name[0].toUpperCase()
          : '?';
      final tp = TextPainter(
        text: TextSpan(
          text: initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: r * 0.85,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        center - Offset(tp.width / 2, tp.height / 2),
      );

      // Name label below
      final nameTp = TextPainter(
        text: TextSpan(
          text: node.person.name.split(' ').first,
          style: TextStyle(
            color: Colors.white70,
            fontSize: (11 * scale).clamp(8.0, 14.0),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90 * scale);
      nameTp.paint(
        canvas,
        center + Offset(-nameTp.width / 2, r + 4 * scale),
      );
    }
  }

  void _drawArrow(
      Canvas canvas, Offset from, Offset to, bool mutual, Paint paint) {
    final dir = (to - from);
    final len = dir.distance;
    if (len < 1) return;
    final unit = dir / len;
    final tipOffset = nodeRadius * scale + 4;
    final tip = to - unit * tipOffset;

    const arrowLen = 10.0;
    const arrowAngle = 0.4;
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
        ..color = mutual ? Colors.pinkAccent : Colors.white38
        ..style = PaintingStyle.fill,
    );

    if (mutual) {
      // Also draw reverse arrow
      final fromUnit = -unit;
      final fromTip = from - fromUnit * (-(nodeRadius * scale + 4));
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
          ..color = Colors.pinkAccent
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawEdgeLabel(
      Canvas canvas, Offset from, Offset to, String label, bool mutual) {
    final mid = (from + to) / 2;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: mutual
              ? Colors.pinkAccent.withValues(alpha: 0.9)
              : Colors.white38,
          fontSize: (10 * scale).clamp(7.0, 12.0),
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Subtle bg
    final bgRect = Rect.fromCenter(
      center: mid,
      width: tp.width + 6,
      height: tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      Paint()..color = const Color(0xCC0D0D0D),
    );
    tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}