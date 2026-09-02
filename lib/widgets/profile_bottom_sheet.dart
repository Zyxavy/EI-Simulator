import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/db_helper.dart';
import '../models/person.dart';
import '../models/relationship.dart';
import '../models/relationship_image.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/person_provider.dart';
import '../theme/app_colors.dart';

Future<void> showProfileBottomSheet(BuildContext context, Person person) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.58, 0.95],
      builder: (_, scrollController) => _ProfileSheetContent(
        person: person,
        scrollController: scrollController,
      ),
    ),
  );
}

class _ProfileSheetContent extends StatefulWidget {
  final Person person;
  final ScrollController scrollController;

  const _ProfileSheetContent({required this.person, required this.scrollController});

  @override
  State<_ProfileSheetContent> createState() => _ProfileSheetContentState();
}

class _ProfileSheetContentState extends State<_ProfileSheetContent> {
  late Person _person;
  List<Relationship> _relationships = [];
  Map<int, List<RelationshipImage>> _imagesByRelId = {};
  bool _loading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  late TextEditingController _editNameController;
  late TextEditingController _editDescController;
  late TextEditingController _editPersonalityController;
  String? _editImagePath;
  final ImagePicker _editPicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    _editNameController = TextEditingController();
    _editDescController = TextEditingController();
    _editPersonalityController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _editNameController.dispose();
    _editDescController.dispose();
    _editPersonalityController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final fresh = await DbHelper.instance.getPersonById(_person.id!);
    if (fresh != null) _person = fresh;
    final rels = await DbHelper.instance.getRelationshipsByPersonId(_person.id!);
    final Map<int, List<RelationshipImage>> imgMap = {};
    for (final r in rels) {
      imgMap[r.id!] = await DbHelper.instance.getImagesByRelationshipId(r.id!);
    }
    if (!mounted) return;
    setState(() {
      _relationships = rels;
      _imagesByRelId = imgMap;
      _loading = false;
    });
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Person?', style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold)),
        content: Text('This will delete ${_person.name} and all relationships.',
            style: const TextStyle(color: Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.black54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.vividRed, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    await Provider.of<PersonProvider>(context, listen: false).deletePerson(_person.id!);
    if (!mounted) return;
    Navigator.pop(context); // close sheet
  }

  Future<void> _deleteRel(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Relationship?', style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold)),
        content: const Text('Remove this relationship?', style: TextStyle(color: Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.black54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.vividRed))),
        ],
      ),
    );
    if (ok != true) return;
    await DbHelper.instance.deleteRelationship(id);
    if (!mounted) return;
    await Provider.of<PersonProvider>(context, listen: false).loadAll();
    await _loadData();
  }

  void _enterEditMode() {
    _editNameController.text = _person.name;
    _editDescController.text = _person.description;
    _editPersonalityController.text = _person.personality;
    _editImagePath = _person.imagePath;
    setState(() => _isEditing = true);
  }

  void _cancelEdit() {
    setState(() => _isEditing = false);
  }

  Future<void> _pickEditImage() async {
    final XFile? p = await _editPicker.pickImage(source: ImageSource.gallery);
    if (p != null) setState(() => _editImagePath = p.path);
  }

  Future<void> _saveEdit() async {
    final name = _editNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name must not be empty')));
      return;
    }
    if (_editImagePath == null || _editImagePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please pick a profile image')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final updated = _person.copyWith(
        name: name,
        description: _editDescController.text.trim(),
        personality: _editPersonalityController.text.trim(),
        imagePath: _editImagePath!,
      );
      await Provider.of<PersonProvider>(context, listen: false).updatePerson(updated);
      // Refresh local
      _person = updated;
      await _loadData();
      if (!mounted) return;
      setState(() => _isEditing = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "$name"'), backgroundColor: AppColors.vividRed, behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildHeader() {
    if (_isEditing) {
      // Editable header: tappable avatar + text fields
      final isEditAsset = _editImagePath != null && _editImagePath!.startsWith('assets/');
      final editFileExists = _editImagePath != null && !_editImagePath!.startsWith('assets/') && File(_editImagePath!).existsSync();
      Widget editAvatar;
      if (isEditAsset) {
        editAvatar = CircleAvatar(radius: 34, backgroundImage: AssetImage(_editImagePath!), backgroundColor: Colors.white);
      } else if (editFileExists) {
        editAvatar = CircleAvatar(radius: 34, backgroundImage: FileImage(File(_editImagePath!)));
      } else if (_editImagePath != null && _editImagePath!.isNotEmpty) {
        editAvatar = CircleAvatar(radius: 34, backgroundImage: FileImage(File(_editImagePath!)), backgroundColor: Colors.white);
      } else {
        editAvatar = const CircleAvatar(radius: 34, backgroundColor: Colors.white, child: Icon(Icons.person, size: 34, color: AppColors.vividRed));
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _pickEditImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)]),
                  child: editAvatar,
                ),
                Container(
                  decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name field
                SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _editNameController,
                    style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Name',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white), borderRadius: BorderRadius.circular(10)),
                      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.coral, width: 1.4), borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Personality inline edit
                SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _editPersonalityController,
                    style: const TextStyle(color: Colors.black87, fontSize: 11),
                    decoration: InputDecoration(
                      hintText: 'Personality (comma separated)',
                      hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.35), fontSize: 10),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.8)), borderRadius: BorderRadius.circular(20)),
                      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.coral), borderRadius: BorderRadius.all(Radius.circular(20))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final isAsset = _person.imagePath.startsWith('assets/');
    final fileExists = !isAsset && File(_person.imagePath).existsSync();
    Widget avatar;
    if (isAsset) {
      avatar = CircleAvatar(radius: 34, backgroundImage: AssetImage(_person.imagePath), backgroundColor: Colors.white, onBackgroundImageError: (_, _) {});
    } else if (fileExists) {
      avatar = CircleAvatar(radius: 34, backgroundImage: FileImage(File(_person.imagePath)));
    } else {
      avatar = const CircleAvatar(radius: 34, backgroundColor: Colors.white, child: Icon(Icons.person, size: 34, color: AppColors.vividRed));
    }

    final pill = _person.personality.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList().isNotEmpty
        ? _person.personality.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).first
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)]),
          child: avatar,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_person.name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              if (pill.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(20)),
                  child: Text(pill, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddRelationshipInEdit() async {
    final provider = Provider.of<PersonProvider>(context, listen: false);
    final persons = provider.persons.where((p) => p.id != _person.id).toList();
    if (persons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other people to relate to yet')));
      return;
    }
    Person? selectedTo;
    final labelController = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Relationship', style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Person>(
              dropdownColor: Colors.white,
              decoration: InputDecoration(
                labelText: 'To',
                labelStyle: const TextStyle(color: Colors.black54),
                enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.black54), borderRadius: BorderRadius.all(Radius.circular(8))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.coral), borderRadius: BorderRadius.all(Radius.circular(8))),
              ),
              items: persons.map((p) => DropdownMenuItem(value: p, child: Text(p.name, style: const TextStyle(color: Colors.black87)))).toList(),
              onChanged: (v) => selectedTo = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              decoration: InputDecoration(
                labelText: 'Label (Crush, Ex, Situationship)',
                labelStyle: const TextStyle(color: Colors.black54, fontSize: 12),
                enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.black54), borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.coral), borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.black54))),
          TextButton(
            onPressed: () {
              if (selectedTo == null || labelController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select person and label')));
                return;
              }
              Navigator.pop(ctx, {'to': selectedTo, 'label': labelController.text.trim()});
            },
            child: const Text('Add', style: TextStyle(color: AppColors.vividRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (result != null) {
      final toPerson = result['to'] as Person;
      final label = result['label'] as String;
      final now = DateTime.now().toIso8601String();
      final rel = Relationship(fromPersonId: _person.id!, toPersonId: toPerson.id!, label: label, isMutual: false, createdAt: now);
      await DbHelper.instance.insertRelationship(rel);
      if (!mounted) return;
      await Provider.of<PersonProvider>(context, listen: false).loadAll();
      await _loadData();
    }
  }

  Widget _buildRelationshipsCompact() {
    // Edit mode: wizard-style Add Relationships row with chips + plus (only possible when editing)
    if (_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Relationships', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._relationships.map((rel) {
                  final otherId = rel.fromPersonId == _person.id ? rel.toPersonId : rel.fromPersonId;
                  return FutureBuilder<Person?>(
                    future: DbHelper.instance.getPersonById(otherId),
                    builder: (context, snap) {
                      final p = snap.data;
                      final path = p?.imagePath;
                      Widget av;
                      if (path == null) {
                        av = const CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.person, size: 14, color: AppColors.vividRed));
                      } else if (path.startsWith('assets/')) {
                        av = CircleAvatar(radius: 14, backgroundImage: AssetImage(path), backgroundColor: Colors.white);
                      } else if (File(path).existsSync()) {
                        av = CircleAvatar(radius: 14, backgroundImage: FileImage(File(path)));
                      } else {
                        av = const CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.person, size: 14, color: AppColors.vividRed));
                      }
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.coral.withValues(alpha: 0.3))),
                        child: Row(
                          children: [
                            av,
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(p?.name.split(' ').first ?? 'Unknown', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87)),
                                Text(rel.label, style: const TextStyle(fontSize: 9, color: AppColors.coral)),
                              ],
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _deleteRel(rel.id!),
                              child: const Icon(Icons.close, size: 14, color: Colors.black45),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }),
                // Plus button - only in edit mode (wizard style)
                GestureDetector(
                  onTap: _showAddRelationshipInEdit,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
          if (_relationships.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Tap + to add a relationship', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
            ),
        ],
      );
    }

    // View mode: read-only small avatars row (no add)
    if (_relationships.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RELATIONSHIPS:', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          const Text('None', style: TextStyle(color: Colors.white60, fontStyle: FontStyle.italic, fontSize: 12)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RELATIONSHIPS:', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _relationships.length,
            itemBuilder: (context, i) {
              final rel = _relationships[i];
              final otherId = rel.fromPersonId == _person.id ? rel.toPersonId : rel.fromPersonId;
              return FutureBuilder<Person?>(
                future: DbHelper.instance.getPersonById(otherId),
                builder: (context, snap) {
                  final p = snap.data;
                  final path = p?.imagePath;
                  Widget av;
                  if (path == null) {
                    av = const CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.person, size: 14, color: AppColors.vividRed));
                  } else if (path.startsWith('assets/')) {
                    av = CircleAvatar(radius: 16, backgroundImage: AssetImage(path), backgroundColor: Colors.white);
                  } else if (File(path).existsSync()) {
                    av = CircleAvatar(radius: 16, backgroundImage: FileImage(File(path)));
                  } else {
                    av = const CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.person, size: 14, color: AppColors.vividRed));
                  }
                  return Container(
                    margin: EdgeInsets.only(right: 6, left: i == 0 ? 0 : 0),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        av,
                        Positioned(
                          bottom: -2,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.coral, width: 0.8)),
                            child: Text(rel.label, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: AppColors.vividRed)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addPhoto() async {
    if (_relationships.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a relationship first to add photos')),
      );
      return;
    }
    final XFile? picked = await _editPicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    // Attach to first relationship (or most recent) - simple for now
    final targetRelId = _relationships.first.id!;
    await DbHelper.instance.insertRelationshipImage(
      RelationshipImage(relationshipId: targetRelId, imagePath: picked.path),
    );
    await _loadData();
    if (!mounted) return;
    await Provider.of<PersonProvider>(context, listen: false).loadAll();
  }

  void _expandPhoto(ImageProvider provider) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image(image: provider, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGallery() {
    final allImages = _imagesByRelId.values.expand((e) => e).toList();
    final isEditingGallery = _isEditing;

    // Empty state - show add tile only in edit mode
    if (allImages.isEmpty) {
      if (!isEditingGallery) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFFE8E8E8), borderRadius: BorderRadius.circular(4)),
          child: Center(
            child: Text('No photos', style: TextStyle(color: Colors.black.withValues(alpha: 0.3), fontSize: 11)),
          ),
        );
      }
      // Edit mode empty - show add tile
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFE8E8E8), borderRadius: BorderRadius.circular(4)),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, idx) {
            return GestureDetector(
              onTap: _addPhoto,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.coral, width: 1.2),
                ),
                child: const Icon(Icons.add_a_photo, color: AppColors.coral, size: 28),
              ),
            );
          },
        ),
      );
    }

    // Gallery grid - vertical, requires scrolling down to see more
    final itemCount = isEditingGallery ? allImages.length + 1 : allImages.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFE8E8E8), borderRadius: BorderRadius.circular(4)),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, idx) {
          // Last tile in edit mode is Add button
          if (isEditingGallery && idx == allImages.length) {
            return GestureDetector(
              onTap: _addPhoto,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.coral, width: 1.2),
                ),
                child: const Icon(Icons.add_a_photo, color: AppColors.coral, size: 28),
              ),
            );
          }
          final img = allImages[idx];
          final isAsset = img.imagePath.startsWith('assets/');
          final prov = isAsset ? AssetImage(img.imagePath) as ImageProvider : FileImage(File(img.imagePath));
          return GestureDetector(
            onTap: () async {
              if (isEditingGallery) {
                // Only removable in edit mode
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.bgLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: const Text('Remove photo?', style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold, fontSize: 14)),
                    content: const Text('Delete this photo?', style: TextStyle(color: Colors.black54, fontSize: 12)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.black54))),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.vividRed))),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await DbHelper.instance.deleteRelationshipImage(img.id!);
                  await _loadData();
                  if (!mounted) return;
                  if (!context.mounted) return;
                  await Provider.of<PersonProvider>(context, listen: false).loadAll();
                }
              } else {
                // Read mode: expand to view
                _expandPhoto(prov);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                image: DecorationImage(image: prov, fit: BoxFit.cover, onError: (_, _) {}),
                color: Colors.white,
              ),
              child: isEditingGallery
                  ? Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                        child: const Icon(Icons.close, size: 10, color: Colors.white),
                      ),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.vividRed,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Drag handle
          Center(
            child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Stack(
                    children: [
                      // Scrollable content — gallery at very bottom so user must scroll to see it
                      ListView(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 12),
                          _isEditing
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white),
                                  ),
                                  child: TextField(
                                    controller: _editDescController,
                                    maxLines: 4,
                                    style: const TextStyle(color: Colors.black87, fontSize: 12, height: 1.4),
                                    decoration: InputDecoration(
                                      hintText: 'Description',
                                      hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.35), fontSize: 12),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.all(10),
                                    ),
                                  ),
                                )
                              : RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.5),
                                    children: [
                                      const TextSpan(text: 'Descrip......', style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 10)),
                                      TextSpan(text: _person.description.isEmpty ? ' No description.' : _person.description, style: const TextStyle(fontStyle: FontStyle.italic)),
                                    ],
                                  ),
                                ),
                          const SizedBox(height: 14),
                          _buildRelationshipsCompact(),
                          const SizedBox(height: 14),
                          // Detailed sections revealed on scroll when sheet expands
                          const Divider(color: Colors.white24, height: 20),
                          _DetailedSections(person: _person, relationships: _relationships),
                          const SizedBox(height: 20),
                          // Gallery at bottom — requires scrolling past details to see photos
                          const Text('PHOTOS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                          const SizedBox(height: 8),
                          _buildGallery(),
                          const SizedBox(height: 8),
                          Text('Scroll to see all photos • Tap + on image row in Add Relationship to add more',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 9, fontStyle: FontStyle.italic),
                              textAlign: TextAlign.center),
                        ],
                      ),
                      // Sticky bottom bar — edit (or check when editing) + delete / cancel when editing
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                          decoration: BoxDecoration(
                            color: AppColors.vividRed,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 12,
                                offset: const Offset(0, -4),
                              ),
                            ],
                            border: const Border(top: BorderSide(color: Colors.white24, width: 0.6)),
                          ),
                          child: SafeArea(
                            top: false,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Edit / Check / Cancel logic
                                if (_isEditing) ...[
                                  // Cancel
                                  GestureDetector(
                                    onTap: _isSaving ? null : _cancelEdit,
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1)),
                                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Save (check)
                                  GestureDetector(
                                    onTap: _isSaving ? null : _saveEdit,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 8, offset: const Offset(0, 2))]),
                                      child: _isSaving
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: Padding(
                                                padding: EdgeInsets.all(14),
                                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.vividRed),
                                              ),
                                            )
                                          : const Icon(Icons.check, color: AppColors.vividRed, size: 22),
                                    ),
                                  ),
                                ] else ...[
                                  // Edit
                                  GestureDetector(
                                    onTap: _enterEditMode,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                          color: AppColors.coral,
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 8, offset: const Offset(0, 2))]),
                                      child: const Icon(Icons.edit, color: Colors.white, size: 20),
                                    ),
                                  ),
                                  const SizedBox(width: 28),
                                  // Delete
                                  GestureDetector(
                                    onTap: _confirmDelete,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                          color: AppColors.coral,
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 8, offset: const Offset(0, 2))]),
                                      child: const Icon(Icons.delete, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailedSections extends StatelessWidget {
  final Person person;
  final List<Relationship> relationships;
  const _DetailedSections({required this.person, required this.relationships});

  @override
  Widget build(BuildContext context) {
    final loves = relationships.where((r) => r.fromPersonId == person.id).toList();
    final lovedBy = relationships.where((r) => r.toPersonId == person.id).toList();

    Widget section(String title, List<Relationship> rels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          if (rels.isEmpty)
            const Text('None', style: TextStyle(color: Colors.white60, fontStyle: FontStyle.italic, fontSize: 12))
          else
            ...rels.map((rel) {
              final otherId = rel.fromPersonId == person.id ? rel.toPersonId : rel.fromPersonId;
              return FutureBuilder<Person?>(
                future: DbHelper.instance.getPersonById(otherId),
                builder: (context, snap) {
                  final name = snap.data?.name ?? 'Unknown';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.bgLight, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Expanded(child: Text(name, style: const TextStyle(color: Color(0xFF3A0000), fontWeight: FontWeight.w600, fontSize: 12))),
                        Text(rel.label + (rel.isMutual ? ' • Mutual' : ''), style: TextStyle(color: rel.isMutual ? AppColors.vividRed : Colors.black54, fontSize: 10)),
                      ],
                    ),
                  );
                },
              );
            }),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('Loves', loves),
        const SizedBox(height: 12),
        section('Loved By', lovedBy),
      ],
    );
  }
}
