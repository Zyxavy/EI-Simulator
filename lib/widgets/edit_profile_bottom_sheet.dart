import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/person.dart';
import '../providers/person_provider.dart';
import '../theme/app_colors.dart';

Future<bool?> showEditProfileBottomSheet(BuildContext context, Person person) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.62, 0.95],
      builder: (_, controller) => _EditSheetContent(person: person, scrollController: controller),
    ),
  );
}

class _EditSheetContent extends StatefulWidget {
  final Person person;
  final ScrollController scrollController;
  const _EditSheetContent({required this.person, required this.scrollController});

  @override
  State<_EditSheetContent> createState() => _EditSheetContentState();
}

class _EditSheetContentState extends State<_EditSheetContent> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _personalityController;
  String? _imagePath;
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person.name);
    _descController = TextEditingController(text: widget.person.description);
    _personalityController = TextEditingController(text: widget.person.personality);
    _imagePath = widget.person.imagePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _personalityController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? p = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (p != null) setState(() => _imagePath = p.path);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name must not be empty')));
      return;
    }
    if (_imagePath == null || _imagePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please pick a profile image')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final provider = Provider.of<PersonProvider>(context, listen: false);
      final updated = widget.person.copyWith(
        name: name,
        description: _descController.text.trim(),
        personality: _personalityController.text.trim(),
        imagePath: _imagePath!,
      );
      await provider.updatePerson(updated);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile updated: $name'), backgroundColor: AppColors.vividRed));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAsset = _imagePath != null && _imagePath!.startsWith('assets/');
    final fileExists = _imagePath != null && !_imagePath!.startsWith('assets/') && File(_imagePath!).existsSync();

    Widget avatar;
    if (isAsset) {
      avatar = CircleAvatar(radius: 42, backgroundImage: AssetImage(_imagePath!), backgroundColor: Colors.white);
    } else if (fileExists) {
      avatar = CircleAvatar(radius: 42, backgroundImage: FileImage(File(_imagePath!)));
    } else if (_imagePath != null && _imagePath!.isNotEmpty) {
      avatar = CircleAvatar(radius: 42, backgroundImage: FileImage(File(_imagePath!)), backgroundColor: Colors.white);
    } else {
      avatar = const CircleAvatar(radius: 42, backgroundColor: Colors.white, child: Icon(Icons.person, size: 36, color: AppColors.vividRed));
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                const Center(child: Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87))),
                const SizedBox(height: 4),
                Center(child: Text('Drag down to minimize, scroll to expand', style: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 10))),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.coral, width: 2)),
                          child: avatar,
                        ),
                        Container(
                          decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Name', style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.black26), borderRadius: BorderRadius.circular(10)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.coral, width: 1.4), borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Description', style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                TextField(
                  controller: _descController,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(12),
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.black26), borderRadius: BorderRadius.circular(10)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.coral, width: 1.4), borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Personality (comma-separated)', style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                TextField(
                  controller: _personalityController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    hintText: 'e.g. Tsundere, Overconfident',
                    hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3), fontSize: 11),
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.black26), borderRadius: BorderRadius.circular(10)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.coral, width: 1.4), borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const SizedBox(height: 10),
                // Quick tags preview
                Builder(builder: (context) {
                  final tags = _personalityController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                  if (tags.isEmpty) return const SizedBox.shrink();
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tags
                        .map((t) => Chip(
                              label: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11)),
                              backgroundColor: AppColors.coral,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ))
                        .toList(),
                  );
                }),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.vividRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: Colors.black.withValues(alpha: 0.5))),
                  ),
                ),
              ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
