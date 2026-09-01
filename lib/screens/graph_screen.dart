import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';

import '../providers/person_provider.dart';
import '../models/person.dart';
import '../models/relationship.dart';
import 'profile_screen.dart';
import 'add_edit_person_screen.dart';
import 'search_screen.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  final Graph graph = Graph()..isTree = false;
  final FruchtermanReingoldAlgorithm algorithm = FruchtermanReingoldAlgorithm(
    FruchtermanReingoldConfiguration(),
  );

  // Maps person ID → graphview Node
  final Map<int, Node> _nodeMap = {};

  void _buildGraph(List<Person> persons, List<Relationship> relationships) {
    graph.nodes.clear();
    graph.edges.clear();
    _nodeMap.clear();

    for (final person in persons) {
      final pid = person.id;
      if (pid == null) {
        debugPrint('Skipping person with null id: ${person.name}');
        continue;
      }
      final node = Node.Id(pid);
      _nodeMap[pid] = node;
      graph.addNode(node);
    }

    for (final rel in relationships) {
      final from = _nodeMap[rel.fromPersonId];
      final to = _nodeMap[rel.toPersonId];
      if (from != null && to != null) {
        graph.addEdge(
          from,
          to,
          paint: Paint()
            ..color = rel.isMutual ? Colors.pinkAccent : Colors.white38
            ..strokeWidth = rel.isMutual ? 2.5 : 1.5,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'EI Simulator',
          style: TextStyle(color: Colors.white),
        ),
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

          _buildGraph(provider.persons, provider.relationships);

          return InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(100),
            minScale: 0.3,
            maxScale: 2.5,
            child: GraphView(
              graph: graph,
              algorithm: algorithm,
              paint: Paint()..color = Colors.white38,
              builder: (Node node) {
                final raw = node.key?.value;
                if (raw is! int) {
                  debugPrint('GraphView builder: node key is not int: $raw');
                  return const SizedBox.shrink();
                }
                final personId = raw;
                Person? person;
                try {
                  person = provider.persons.firstWhere((p) => p.id == personId);
                } catch (_) {
                  debugPrint('GraphView builder: person $personId not found');
                  return const SizedBox.shrink();
                }
                return _buildPersonNode(person);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEditPersonScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPersonNode(Person person) {
    final isAsset = person.imagePath.startsWith('assets/');
    final ImageProvider? bgImage = isAsset
        ? AssetImage(person.imagePath)
        : FileImage(File(person.imagePath));

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfileScreen(person: person)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: bgImage,
            backgroundColor: Colors.grey[800],
            onBackgroundImageError: (_, _) {},
          ),
          const SizedBox(height: 4),
          Text(
            person.name.split(' ').first, // first name only, less cluttered
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
