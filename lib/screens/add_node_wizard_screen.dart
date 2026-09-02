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

class _PendingRel {
  final Person to;
  final String label;
  _PendingRel({required this.to, required this.label});
}

class AddNodeWizardScreen extends StatefulWidget {
  const AddNodeWizardScreen({super.key});

  @override
  State<AddNodeWizardScreen> createState() => _AddNodeWizardScreenState();
}

class _AddNodeWizardScreenState extends State<AddNodeWizardScreen> {
  int _step = 0; // 0: info, 1: tags, 2: photos, 3: success
  bool _isSaving = false;

  // Step 1 controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  String? _profileImagePath;
  final List<_PendingRel> _pendingRels = [];
  final ImagePicker _picker = ImagePicker();

  // Step 2 tags
  final List<String> _selectedTags = [];
  final TextEditingController _tagController = TextEditingController();

  // Step 3 photos
  final List<String> _photoPaths = [];

  // Created IDs
  int? _createdPersonId;
  final List<int> _createdRelationshipIds = [];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  double get _progress {
    switch (_step) {
      case 0:
        return 0.33;
      case 1:
        return 0.66;
      case 2:
        return 0.9;
      case 3:
        return 1.0;
      default:
        return 0.33;
    }
  }

  Future<void> _pickProfileImage() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _profileImagePath = picked.path);
    }
  }

  Future<void> _pickPhoto() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _photoPaths.add(picked.path));
    }
  }

  Future<void> _showAddRelationshipDialog() async {
    final provider = Provider.of<PersonProvider>(context, listen: false);
    final persons = provider.persons;
    if (persons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No existing people to relate to yet')),
      );
      return;
    }
    Person? selectedTo;
    final labelController = TextEditingController();

    final result = await showDialog<_PendingRel>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Relationship',
            style: TextStyle(color: Color(0xFF2B0000), fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Person>(
                dropdownColor: Colors.white,
                decoration: InputDecoration(
                  labelText: 'To',
                  labelStyle: const TextStyle(color: Colors.black54),
                  enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.black54),
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: AppColors.coral),
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: persons.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                onChanged: (v) => selectedTo = v,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: labelController,
                decoration: InputDecoration(
                  labelText: 'Label (Crush, Ex, Situationship)',
                  labelStyle: const TextStyle(color: Colors.black54, fontSize: 12),
                  enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.black54),
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: AppColors.coral),
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.black54))),
          TextButton(
            onPressed: () {
              if (selectedTo == null || labelController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select person and label')));
                return;
              }
              Navigator.pop(ctx, _PendingRel(to: selectedTo!, label: labelController.text.trim()));
            },
            child: const Text('Add', style: TextStyle(color: AppColors.vividRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() => _pendingRels.add(result));
    }
  }

  Future<void> _saveStep1() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name must not be empty')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      // Profile image optional, fallback to default asset if not picked
      final imagePath = (_profileImagePath != null && _profileImagePath!.isNotEmpty)
          ? _profileImagePath!
          : 'assets/images/john.png';

      final newPerson = Person(
        name: name,
        description: _descController.text.trim(),
        personality: '', // tags added in step 2
        imagePath: imagePath,
        createdAt: now,
      );
      final provider = Provider.of<PersonProvider>(context, listen: false);
      // Insert via DbHelper to get id, then provider load
      final id = await DbHelper.instance.insertPerson(newPerson);
      _createdPersonId = id;

      // Insert pending relationships
      _createdRelationshipIds.clear();
      for (final pr in _pendingRels) {
        final rel = Relationship(
          fromPersonId: id,
          toPersonId: pr.to.id!,
          label: pr.label,
          isMutual: false,
          createdAt: now,
        );
        final relId = await DbHelper.instance.insertRelationship(rel);
        _createdRelationshipIds.add(relId);
      }

      await provider.loadAll();

      if (!mounted) return;
      setState(() => _step = 1);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveStep2() async {
    if (_createdPersonId == null) return;
    setState(() => _isSaving = true);
    try {
      final person = await DbHelper.instance.getPersonById(_createdPersonId!);
      if (person == null) return;
      final updated = person.copyWith(personality: _selectedTags.join(', '));
      await DbHelper.instance.updatePerson(updated);
      if (!mounted) return;
      await Provider.of<PersonProvider>(context, listen: false).loadAll();
      if (!mounted) return;
      setState(() => _step = 2);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveStep3() async {
    setState(() => _isSaving = true);
    try {
      // Attach photos to first created relationship if exists, otherwise skip DB and just show success
      if (_photoPaths.isNotEmpty && _createdRelationshipIds.isNotEmpty) {
        final targetRelId = _createdRelationshipIds.first;
        for (final path in _photoPaths) {
          await DbHelper.instance.insertRelationshipImage(
            RelationshipImage(relationshipId: targetRelId, imagePath: path),
          );
        }
        if (!mounted) return;
        await Provider.of<PersonProvider>(context, listen: false).loadAll();
      } else if (_photoPaths.isNotEmpty && _createdRelationshipIds.isEmpty) {
        // No relationship to attach to, inform user but still succeed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photos need a relationship to attach to, skipped, but profile was created')),
          );
        }
      }
      if (!mounted) return;
      setState(() => _step = 3);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addTag(String tag) {
    final t = tag.trim();
    if (t.isEmpty) return;
    if (_selectedTags.contains(t)) return;
    setState(() => _selectedTags.add(t));
    _tagController.clear();
  }

  Widget _buildProgressHeader({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.vividRed, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                if (_step == 0) {
                  Navigator.pop(context);
                } else if (_step < 3) {
                  setState(() => _step--);
                }
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: Colors.white,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.vividRed),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
              // Handwritten feel, mock uses casual font
              fontFamily: 'Raleway',
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.5),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProgressHeader(title: 'Enter Information', subtitle: 'What are his personal details?'),
        const SizedBox(height: 28),
        // Profile image picker (optional), circular
        Center(
          child: GestureDetector(
            onTap: _pickProfileImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                _profileImagePath != null && File(_profileImagePath!).existsSync()
                    ? CircleAvatar(
                        radius: 36, backgroundImage: ResizeImage(FileImage(File(_profileImagePath!)), width: 144, height: 144))
                    : _profileImagePath != null && _profileImagePath!.startsWith('assets/')
                        ? CircleAvatar(radius: 36, backgroundImage: AssetImage(_profileImagePath!), backgroundColor: Colors.white)
                        : Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: Colors.black, width: 0.8),
                            ),
                            child: const Icon(Icons.person, size: 32, color: Colors.black38),
                          ),
                Container(
                  decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(5),
                  child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text('Profile photo (optional)', style: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 10)),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width: 88,
              child: Text('Name:', style: TextStyle(color: AppColors.coral, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: SizedBox(
                height: 28,
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    fillColor: Colors.white,
                    filled: true,
                    enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.black, width: 0.9), borderRadius: BorderRadius.circular(2)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppColors.coral), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: SizedBox(
                width: 88,
                child: Text('Description', style: TextStyle(color: AppColors.coral, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ),
            Expanded(
              child: Container(
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: TextField(
                  controller: _descController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(8),
                    hintText: '',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('Add Relationships', style: TextStyle(color: AppColors.coral, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        // Horizontal list of pending rels + add button
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ..._pendingRels.map((pr) {
                final isAsset = pr.to.imagePath.startsWith('assets/');
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.coral.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundImage: isAsset ? AssetImage(pr.to.imagePath) : FileImage(File(pr.to.imagePath)) as ImageProvider,
                        backgroundColor: Colors.white,
                        onBackgroundImageError: (_, _) {},
                      ),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(pr.to.name.split(' ').first, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87)),
                          Text(pr.label, style: const TextStyle(fontSize: 9, color: AppColors.coral)),
                        ],
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() => _pendingRels.remove(pr)),
                        child: const Icon(Icons.close, size: 14, color: Colors.black45),
                      ),
                    ],
                  ),
                );
              }),
              GestureDetector(
                onTap: _showAddRelationshipDialog,
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
        if (_pendingRels.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tap + to add a relationship (optional)', style: TextStyle(color: Colors.black.withValues(alpha: 0.35), fontSize: 10)),
          ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveStep1,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.vividRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    // Suggested tags from existing persons
    final provider = Provider.of<PersonProvider>(context, listen: false);
    final allTags = provider.persons
        .expand((p) => p.personality.split(',').map((s) => s.trim()))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProgressHeader(title: 'Add Tags', subtitle: 'What describes him best?'),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: _tagController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Add a tag (e.g. Tsundere)',
                    hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3), fontSize: 11),
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.black, width: 0.9), borderRadius: BorderRadius.circular(2)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppColors.coral), borderRadius: BorderRadius.circular(2)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add, color: AppColors.vividRed, size: 18),
                      onPressed: () => _addTag(_tagController.text),
                    ),
                  ),
                  onSubmitted: _addTag,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_selectedTags.isNotEmpty) ...[
          const Text('Selected tags:', style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedTags
                .map((t) => Chip(
                      label: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: AppColors.coral,
                      deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white),
                      onDeleted: () => setState(() => _selectedTags.remove(t)),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
        ],
        if (allTags.isNotEmpty) ...[
          Text('Suggestions:', style: TextStyle(color: Colors.black.withValues(alpha: 0.5), fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allTags.take(12).map((t) {
              final selected = _selectedTags.contains(t);
              return FilterChip(
                label: Text(t, style: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 11)),
                selected: selected,
                selectedColor: AppColors.vividRed,
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                side: BorderSide(color: selected ? AppColors.vividRed : Colors.black26),
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedTags.add(t);
                    } else {
                      _selectedTags.remove(t);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
        const Spacer(),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 1), // Actually this is step 2, go back to 0? but tag step skip
              child: Text('Skip', style: TextStyle(color: Colors.black.withValues(alpha: 0.4))),
            ),
            const Spacer(),
            Expanded(
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveStep2,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.vividRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isSaving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProgressHeader(title: 'Add Photos', subtitle: 'Add memories together? (optional)'),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 0.9),
            borderRadius: BorderRadius.circular(2),
          ),
          child: SizedBox(
            height: 80,
            child: _photoPaths.isEmpty
                ? Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.bgLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black26),
                        ),
                        child: const Icon(Icons.add_a_photo, color: Colors.black38),
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photoPaths.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _photoPaths.length) {
                        return GestureDetector(
                          onTap: _pickPhoto,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.bgLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black26),
                            ),
                            child: const Icon(Icons.add_a_photo, color: Colors.black38),
                          ),
                        );
                      }
                      final path = _photoPaths[index];
                      return GestureDetector(
                        onTap: () => setState(() => _photoPaths.removeAt(index)),
                        child: Container(
                          width: 80,
                          height: 80,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                                image: ResizeImage(FileImage(File(path)), width: 160, height: 160), fit: BoxFit.cover),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: const Align(
                            alignment: Alignment.topRight,
                            child: Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text('These photos will be attached to the first relationship. Tap photo to remove.',
            style: TextStyle(color: Colors.black.withValues(alpha: 0.35), fontSize: 10)),
        if (_createdRelationshipIds.isEmpty && _photoPaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('No relationship created, photos will be skipped.',
                style: TextStyle(color: AppColors.vividRed.withValues(alpha: 0.7), fontSize: 10)),
          ),
        const Spacer(),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 1),
              child: Text('Back', style: TextStyle(color: Colors.black.withValues(alpha: 0.5))),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _isSaving ? null : () => setState(() => _step = 3), // skip photos
              child: Text('Skip', style: TextStyle(color: Colors.black.withValues(alpha: 0.5))),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveStep3,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.vividRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        _buildProgressHeader(title: 'Success!', subtitle: ''),
        const SizedBox(height: 40),
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(color: AppColors.vividRed, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 42),
        ),
        const SizedBox(height: 20),
        const Text('Profile Created!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 8),
        Text('Node "${_nameController.text.trim()}" is now on the graph.',
            style: TextStyle(color: Colors.black.withValues(alpha: 0.5), fontSize: 12), textAlign: TextAlign.center),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              // Pop to root and refresh graph
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.vividRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_step) {
      case 0:
        body = _buildStep1();
        break;
      case 1:
        body = _buildStep2();
        break;
      case 2:
        body = _buildStep3();
        break;
      case 3:
        body = _buildSuccess();
        break;
      default:
        body = _buildStep1();
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: body,
        ),
      ),
    );
  }
}
