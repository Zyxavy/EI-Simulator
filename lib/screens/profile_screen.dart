import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/db_helper.dart';
import '../models/person.dart';
import '../models/relationship.dart';
import '../models/relationship_image.dart';
import '../providers/person_provider.dart';
import 'add_edit_person_screen.dart';
import 'add_edit_relationship_screen.dart';

class ProfileScreen extends StatefulWidget {
  final Person person;

  const ProfileScreen({super.key, required this.person});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Person _person;
  List<Relationship> _relationships = [];
  Map<int, List<RelationshipImage>> _imagesByRelId = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    // Fetch fresh person data (in case it was updated)
    final freshPerson = await DbHelper.instance.getPersonById(_person.id!);
    if (freshPerson != null) _person = freshPerson;

    final rels = await DbHelper.instance.getRelationshipsByPersonId(
      _person.id!,
    );
    final Map<int, List<RelationshipImage>> imgMap = {};
    for (final rel in rels) {
      final imgs = await DbHelper.instance.getImagesByRelationshipId(rel.id!);
      imgMap[rel.id!] = imgs;
    }
    if (!mounted) return;
    setState(() {
      _relationships = rels;
      _imagesByRelId = imgMap;
      _loading = false;
    });
  }

  List<Relationship> get _loves =>
      _relationships.where((r) => r.fromPersonId == _person.id).toList();
  List<Relationship> get _lovedBy =>
      _relationships.where((r) => r.toPersonId == _person.id).toList();

  Future<void> _confirmDeletePerson() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Person?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will delete ${_person.name} and all their relationships. This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final provider = Provider.of<PersonProvider>(context, listen: false);
    await provider.deletePerson(_person.id!);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _deleteRelationship(int relId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Relationship?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Remove this relationship?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DbHelper.instance.deleteRelationship(relId);
    if (!mounted) return;
    if (!context.mounted) return;
    await Provider.of<PersonProvider>(context, listen: false).loadAll();
    await _loadData();
  }

  Future<void> _deleteImage(int imageId, int relId) async {
    await DbHelper.instance.deleteRelationshipImage(imageId);
    await _loadData();
  }

  Widget _buildHeader() {
    final isAsset = _person.imagePath.startsWith('assets/');
    final fileExists = !isAsset && File(_person.imagePath).existsSync();
    Widget avatar;
    if (isAsset) {
      avatar = CircleAvatar(
        radius: 50,
        backgroundImage: AssetImage(_person.imagePath),
        backgroundColor: Colors.grey[800],
        onBackgroundImageError: (_, _) {},
      );
    } else if (fileExists) {
      avatar = CircleAvatar(
        radius: 50,
        backgroundImage: FileImage(File(_person.imagePath)),
      );
    } else {
      avatar = CircleAvatar(
        radius: 50,
        backgroundColor: Colors.grey[800],
        child: const Icon(Icons.person, size: 50, color: Colors.white54),
      );
    }

    final personalityTags = _person.personality
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return Column(
      children: [
        avatar,
        const SizedBox(height: 12),
        Text(
          _person.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _person.description,
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: personalityTags
              .map(
                (tag) => Chip(
                  label: Text(
                    tag,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  backgroundColor: Colors.pinkAccent.withValues(alpha: 0.3),
                  side: const BorderSide(color: Colors.pinkAccent),
                  visualDensity: VisualDensity.compact,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildRelationshipSection(String title, List<Relationship> rels) {
    if (rels.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text('None', style: TextStyle(color: Colors.white38)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...rels.map((rel) {
          // Determine the other person's ID
          final otherId = rel.fromPersonId == _person.id
              ? rel.toPersonId
              : rel.fromPersonId;
          return FutureBuilder<Person?>(
            future: DbHelper.instance.getPersonById(otherId),
            builder: (context, snapshot) {
              final otherName = snapshot.data?.name ?? 'Unknown (#$otherId)';
              final otherAvatar = snapshot.data?.imagePath;
              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: otherAvatar == null
                      ? CircleAvatar(
                          backgroundColor: Colors.grey[800],
                          child: const Icon(
                            Icons.person,
                            color: Colors.white54,
                          ),
                        )
                      : otherAvatar.startsWith('assets/')
                      ? CircleAvatar(
                          backgroundImage: AssetImage(otherAvatar),
                          onBackgroundImageError: (_, _) {},
                        )
                      : CircleAvatar(
                          backgroundImage: FileImage(File(otherAvatar)),
                          onBackgroundImageError: (_, _) {},
                        ),
                  title: Text(
                    otherName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    rel.label + (rel.isMutual ? ' • Mutual' : ''),
                    style: TextStyle(
                      color: rel.isMutual ? Colors.pinkAccent : Colors.white60,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.white60,
                          size: 20,
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AddEditRelationshipScreen(relationship: rel),
                            ),
                          );
                          await _loadData();
                          if (!mounted) return;
                          if (!context.mounted) return;
                          await Provider.of<PersonProvider>(
                            context,
                            listen: false,
                          ).loadAll();
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: () => _deleteRelationship(rel.id!),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }

  Widget _buildGallery() {
    final allImages = _imagesByRelId.values.expand((e) => e).toList();
    if (allImages.isEmpty) {
      return const Text(
        'No relationship images yet.',
        style: TextStyle(color: Colors.white38),
      );
    }
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: allImages.length,
        itemBuilder: (context, index) {
          final img = allImages[index];
          final isAsset = img.imagePath.startsWith('assets/');
          ImageProvider provider;
          if (isAsset) {
            provider = AssetImage(img.imagePath);
          } else {
            provider = FileImage(File(img.imagePath));
          }
          return GestureDetector(
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.grey[900],
                  title: const Text(
                    'Remove image?',
                    style: TextStyle(color: Colors.white),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'Remove',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await _deleteImage(img.id!, img.relationshipId);
              }
            },
            child: Container(
              width: 100,
              height: 100,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: provider,
                  fit: BoxFit.cover,
                  onError: (_, _) {},
                ),
                color: Colors.grey[850],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_person.name, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddEditPersonScreen(person: _person),
                ),
              );
              await _loadData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: _confirmDeletePerson,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: _buildHeader()),
                  const SizedBox(height: 24),
                  _buildRelationshipSection('Loves', _loves),
                  const SizedBox(height: 16),
                  _buildRelationshipSection('Loved By', _lovedBy),
                  const SizedBox(height: 16),
                  const Text(
                    'Gallery',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildGallery(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AddEditRelationshipScreen(fromPerson: _person),
                          ),
                        );
                        await _loadData();
                        if (!mounted) return;
                        if (!context.mounted) return;
                        await Provider.of<PersonProvider>(
                          context,
                          listen: false,
                        ).loadAll();
                      },
                      icon: const Icon(Icons.favorite, color: Colors.white),
                      label: const Text(
                        'Add Relationship',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pinkAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
