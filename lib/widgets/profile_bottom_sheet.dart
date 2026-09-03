import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../database/db_helper.dart';
import '../models/person.dart';
import '../models/relationship.dart';
import '../models/relationship_image.dart';
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
  Map<int, Person> _personsById = {};
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
    // Parallelize N+1 image queries — was sequential loop causing jank on main thread
    final imageLists = await Future.wait(
      rels.map((r) => DbHelper.instance.getImagesByRelationshipId(r.id!)),
    );
    final Map<int, List<RelationshipImage>> imgMap = {
      for (int i = 0; i < rels.length; i++) rels[i].id!: imageLists[i],
    };
    // Build synchronous person lookup map from provider (avoids FutureBuilder per relationship)
    Map<int, Person> personsById = _personsById;
    if (mounted) {
      try {
        final provider = Provider.of<PersonProvider>(context, listen: false);
        personsById = {for (final p in provider.persons) p.id!: p};
        // Ensure current person also present
        personsById[_person.id!] = _person;
      } catch (_) {
        // fallback: fetch from DB if provider not ready
        final all = await DbHelper.instance.getAllPersons();
        personsById = {for (final p in all) p.id!: p};
      }
    }
    if (!mounted) return;
    setState(() {
      _relationships = rels;
      _imagesByRelId = imgMap;
      _personsById = personsById;
      _loading = false;
    });
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Person?',
            style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold)),
        content: Text('This will delete ${_person.name} and all relationships.',
            style: const TextStyle(color: Colors.black54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.vividRed, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    await Provider.of<PersonProvider>(context, listen: false).deletePerson(_person.id!);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _deleteRel(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Relationship?',
            style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold)),
        content: const Text('Remove this relationship?', style: TextStyle(color: Colors.black54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.vividRed))),
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
    final XFile? p = await _editPicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
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
      _person = updated;
      await _loadData();
      if (!mounted) return;
      setState(() => _isEditing = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Saved "$name"'),
            backgroundColor: AppColors.vividRed,
            behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildHeader() {
    if (_isEditing) {
      final isEditAsset = _editImagePath != null && _editImagePath!.startsWith('assets/');
      // Avoid existsSync on every build for edit avatar — check once and cache via local bool is fine here
      // since this sheet rebuilds rarely (not 60fps). Still guard.
      final editFileExists = _editImagePath != null &&
          !_editImagePath!.startsWith('assets/') &&
          _editImagePath!.isNotEmpty &&
          File(_editImagePath!).existsSync();
      Widget editAvatar;
      if (isEditAsset) {
        editAvatar = CircleAvatar(
            radius: 34, backgroundImage: AssetImage(_editImagePath!), backgroundColor: Colors.white);
      } else if (editFileExists) {
        editAvatar = CircleAvatar(
            radius: 34,
            backgroundImage: ResizeImage(FileImage(File(_editImagePath!)), width: 140, height: 140));
      } else if (_editImagePath != null && _editImagePath!.isNotEmpty) {
        // File missing — fallback to placeholder instead of crashing FileImage
        editAvatar = const CircleAvatar(
            radius: 34, backgroundColor: Colors.white, child: Icon(Icons.person, size: 34, color: AppColors.vividRed));
      } else {
        editAvatar = const CircleAvatar(
            radius: 34, backgroundColor: Colors.white, child: Icon(Icons.person, size: 34, color: AppColors.vividRed));
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
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)]),
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
                      enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white), borderRadius: BorderRadius.circular(10)),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.coral, width: 1.4),
                          borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
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
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
                          borderRadius: BorderRadius.circular(20)),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.coral),
                          borderRadius: BorderRadius.all(Radius.circular(20))),
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
    Widget avatar;
    if (isAsset) {
      avatar = CircleAvatar(
          radius: 34,
          backgroundImage: AssetImage(_person.imagePath),
          backgroundColor: Colors.white,
          onBackgroundImageError: (_, _) {});
    } else {
      // Use cached existence via _personsById lookup or check file once: if cached map says missing, show placeholder
      // Here we avoid synchronous file IO in build by using ResizeImage with errorBuilder via Image widget fallback
      // But CircleAvatar backgroundImage doesn't have errorBuilder for FileImage missing case, so guard with _personsById file existence?
      // Quick check: if path is file and we have not verified, try existsSync but this branch is not hot (sheet, not 60fps)
      final fileExists = File(_person.imagePath).existsSync();
      if (fileExists) {
        avatar = CircleAvatar(
            radius: 34,
            backgroundImage: ResizeImage(FileImage(File(_person.imagePath)), width: 140, height: 140),
            onBackgroundImageError: (_, _) {});
      } else {
        avatar = const CircleAvatar(
            radius: 34, backgroundColor: Colors.white, child: Icon(Icons.person, size: 34, color: AppColors.vividRed));
      }
    }

    final pill = _person.personality.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList().isNotEmpty
        ? _person.personality.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).first
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)]),
          child: avatar,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_person.name,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              if (pill.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(20)),
                  child:
                      Text(pill, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
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
        title: const Text('Add Relationship',
            style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Person>(
              dropdownColor: Colors.white,
              decoration: InputDecoration(
                labelText: 'To',
                labelStyle: const TextStyle(color: Colors.black54),
                enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black54), borderRadius: BorderRadius.all(Radius.circular(8))),
                focusedBorder:
                    const OutlineInputBorder(borderSide: BorderSide(color: AppColors.coral), borderRadius: BorderRadius.all(Radius.circular(8))),
              ),
              items: persons
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name, style: const TextStyle(color: Colors.black87))))
                  .toList(),
              onChanged: (v) => selectedTo = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              decoration: InputDecoration(
                labelText: 'Label (Crush, Ex, Situationship)',
                labelStyle: const TextStyle(color: Colors.black54, fontSize: 12),
                enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black54), borderRadius: BorderRadius.circular(8)),
                focusedBorder:
                    OutlineInputBorder(borderSide: const BorderSide(color: AppColors.coral), borderRadius: BorderRadius.circular(8)),
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
      final rel =
          Relationship(fromPersonId: _person.id!, toPersonId: toPerson.id!, label: label, isMutual: false, createdAt: now);
      await DbHelper.instance.insertRelationship(rel);
      if (!mounted) return;
      await Provider.of<PersonProvider>(context, listen: false).loadAll();
      await _loadData();
    }
  }

  Widget _buildRelationshipsCompact() {
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
                  final p = _personsById[otherId];
                  final path = p?.imagePath;
                  Widget av;
                  if (path == null) {
                    av = const CircleAvatar(
                        radius: 14, backgroundColor: Colors.white, child: Icon(Icons.person, size: 14, color: AppColors.vividRed));
                  } else if (path.startsWith('assets/')) {
                    av = CircleAvatar(radius: 14, backgroundImage: AssetImage(path), backgroundColor: Colors.white);
                  } else {
                    final exists = File(path).existsSync();
                    if (exists) {
                      av = CircleAvatar(radius: 14, backgroundImage: ResizeImage(FileImage(File(path)), width: 56, height: 56));
                    } else {
                      av = const CircleAvatar(
                          radius: 14, backgroundColor: Colors.white, child: Icon(Icons.person, size: 14, color: AppColors.vividRed));
                    }
                  }
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.coral.withValues(alpha: 0.3))),
                    child: Row(
                      children: [
                        av,
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(p?.name.split(' ').first ?? 'Unknown',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87)),
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
                }),
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
              child:
                  Text('Tap + to add a relationship', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
            ),
        ],
      );
    }

    if (_relationships.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RELATIONSHIPS:',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          const Text('None', style: TextStyle(color: Colors.white60, fontStyle: FontStyle.italic, fontSize: 12)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RELATIONSHIPS:',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _relationships.length,
            addRepaintBoundaries: true,
            itemBuilder: (context, i) {
              final rel = _relationships[i];
              final otherId = rel.fromPersonId == _person.id ? rel.toPersonId : rel.fromPersonId;
              final p = _personsById[otherId];
              final path = p?.imagePath;
              Widget av;
              if (path == null) {
                av = const CircleAvatar(
                    radius: 16, backgroundColor: Colors.white, child: Icon(Icons.person, size: 14, color: AppColors.vividRed));
              } else if (path.startsWith('assets/')) {
                av = CircleAvatar(radius: 16, backgroundImage: AssetImage(path), backgroundColor: Colors.white);
              } else {
                final exists = File(path).existsSync();
                if (exists) {
                  av = CircleAvatar(radius: 16, backgroundImage: ResizeImage(FileImage(File(path)), width: 64, height: 64));
                } else {
                  av = const CircleAvatar(
                      radius: 16, backgroundColor: Colors.white, child: Icon(Icons.person, size: 14, color: AppColors.vividRed));
                }
              }
              return Container(
                margin: const EdgeInsets.only(right: 6),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    av,
                    Positioned(
                      bottom: -2,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.coral, width: 0.8)),
                        child: Text(rel.label,
                            style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: AppColors.vividRed)),
                      ),
                    ),
                  ],
                ),
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
    final XFile? picked = await _editPicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (picked == null) return;
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
              child: Center(child: Image(image: provider, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration:
                      BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
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

    if (allImages.isEmpty) {
      if (!isEditingGallery) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFFE8E8E8), borderRadius: BorderRadius.circular(4)),
          child: Center(child: Text('No photos', style: TextStyle(color: Colors.black.withValues(alpha: 0.3), fontSize: 11))),
        );
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFE8E8E8), borderRadius: BorderRadius.circular(4)),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 1,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
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

    final itemCount = isEditingGallery ? allImages.length + 1 : allImages.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFE8E8E8), borderRadius: BorderRadius.circular(4)),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: false,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, idx) {
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
          final ImageProvider prov = isAsset
              ? AssetImage(img.imagePath)
              : ResizeImage(FileImage(File(img.imagePath)), width: 320, height: 320);
          return RepaintBoundary(
            child: GestureDetector(
              onTap: () async {
                if (isEditingGallery) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.bgLight,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: const Text('Remove photo?',
                          style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold, fontSize: 14)),
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
                          decoration: BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                          child: const Icon(Icons.close, size: 10, color: Colors.white),
                        ),
                      )
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.vividRed,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
                width: 36, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Stack(
                    children: [
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
                                      const TextSpan(
                                          text: 'Descrip......',
                                          style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 10)),
                                      TextSpan(
                                          text: _person.description.isEmpty ? ' No description.' : _person.description,
                                          style: const TextStyle(fontStyle: FontStyle.italic)),
                                    ],
                                  ),
                                ),
                          const SizedBox(height: 14),
                          _buildRelationshipsCompact(),
                          const SizedBox(height: 14),
                          const Divider(color: Colors.white24, height: 20),
                          _DetailedSections(person: _person, relationships: _relationships, personsById: _personsById),
                          const SizedBox(height: 20),
                          const Text('PHOTOS',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                          const SizedBox(height: 8),
                          _buildGallery(),
                          const SizedBox(height: 8),
                          Text('Scroll to see all photos • Tap + on image row in Add Relationship to add more',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 9, fontStyle: FontStyle.italic),
                              textAlign: TextAlign.center),
                        ],
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                          decoration: BoxDecoration(
                            color: AppColors.vividRed,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, -4)),
                            ],
                            border: const Border(top: BorderSide(color: Colors.white24, width: 0.6)),
                          ),
                          child: SafeArea(
                            top: false,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isEditing) ...[
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
                                  GestureDetector(
                                    onTap: _isSaving ? null : _saveEdit,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 8, offset: const Offset(0, 2))
                                      ]),
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
                                  GestureDetector(
                                    onTap: _enterEditMode,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(color: AppColors.coral, shape: BoxShape.circle, boxShadow: [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 8, offset: const Offset(0, 2))
                                      ]),
                                      child: const Icon(Icons.edit, color: Colors.white, size: 20),
                                    ),
                                  ),
                                  const SizedBox(width: 28),
                                  GestureDetector(
                                    onTap: _confirmDelete,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(color: AppColors.coral, shape: BoxShape.circle, boxShadow: [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 8, offset: const Offset(0, 2))
                                      ]),
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
        ),
      ),
    );
  }
}

class _DetailedSections extends StatelessWidget {
  final Person person;
  final List<Relationship> relationships;
  final Map<int, Person> personsById;
  const _DetailedSections({required this.person, required this.relationships, required this.personsById});

  @override
  Widget build(BuildContext context) {
    final loves = relationships.where((r) => r.fromPersonId == person.id).toList();
    final lovedBy = relationships.where((r) => r.toPersonId == person.id).toList();

    Widget section(String title, List<Relationship> rels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          if (rels.isEmpty)
            const Text('None', style: TextStyle(color: Colors.white60, fontStyle: FontStyle.italic, fontSize: 12))
          else
            ...rels.map((rel) {
              final otherId = rel.fromPersonId == person.id ? rel.toPersonId : rel.fromPersonId;
              final name = personsById[otherId]?.name ?? 'Unknown';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.bgLight, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(child: Text(name, style: const TextStyle(color: Color(0xFF3A0000), fontWeight: FontWeight.w600, fontSize: 12))),
                    Text(rel.label + (rel.isMutual ? ' • Mutual' : ''),
                        style: TextStyle(color: rel.isMutual ? AppColors.vividRed : Colors.black54, fontSize: 10)),
                  ],
                ),
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
