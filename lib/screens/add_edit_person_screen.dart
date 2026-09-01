import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/person.dart';
import '../providers/person_provider.dart';

class AddEditPersonScreen extends StatefulWidget {
  final Person? person;

  const AddEditPersonScreen({super.key, this.person});

  @override
  State<AddEditPersonScreen> createState() => _AddEditPersonScreenState();
}

class _AddEditPersonScreenState extends State<AddEditPersonScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _personalityController;
  String? _imagePath;
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  bool get _isEditMode => widget.person != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.person?.description ?? '',
    );
    _personalityController = TextEditingController(
      text: widget.person?.personality ?? '',
    );
    _imagePath = widget.person?.imagePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _personalityController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _imagePath = picked.path);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name must not be empty')));
      return;
    }
    if (_imagePath == null || _imagePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a profile image')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final provider = Provider.of<PersonProvider>(context, listen: false);

      if (_isEditMode) {
        final updated = widget.person!.copyWith(
          name: name,
          description: _descriptionController.text.trim(),
          personality: _personalityController.text.trim(),
          imagePath: _imagePath!,
        );
        await provider.updatePerson(updated);
      } else {
        final newPerson = Person(
          name: name,
          description: _descriptionController.text.trim(),
          personality: _personalityController.text.trim(),
          imagePath: _imagePath!,
          createdAt: now,
        );
        await provider.addPerson(newPerson);
      }

      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildImagePicker() {
    final hasLocalFile =
        _imagePath != null &&
        _imagePath!.isNotEmpty &&
        File(_imagePath!).existsSync();
    final isAssetPath = _imagePath != null && _imagePath!.startsWith('assets/');

    Widget imageWidget;
    if (hasLocalFile) {
      imageWidget = CircleAvatar(
        radius: 50,
        backgroundImage: FileImage(File(_imagePath!)),
      );
    } else if (isAssetPath) {
      imageWidget = CircleAvatar(
        radius: 50,
        backgroundImage: AssetImage(_imagePath!),
        onBackgroundImageError: (_, _) {},
      );
    } else if (_imagePath != null && _imagePath!.isNotEmpty) {
      // Fallback: treat as file path even if not exists yet (picked but not verified)
      imageWidget = CircleAvatar(
        radius: 50,
        backgroundImage: FileImage(File(_imagePath!)),
        backgroundColor: Colors.grey[800],
        onBackgroundImageError: (_, _) {},
      );
    } else {
      imageWidget = CircleAvatar(
        radius: 50,
        backgroundColor: Colors.grey[800],
        child: const Icon(Icons.person, size: 50, color: Colors.white54),
      );
    }

    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          imageWidget,
          Container(
            decoration: const BoxDecoration(
              color: Colors.pinkAccent,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(6),
            child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
          ),
        ],
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
        title: Text(
          _isEditMode ? 'Edit Person' : 'Add Person',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildImagePicker(),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Name *',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.pinkAccent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.pinkAccent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _personalityController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Personality (comma-separated)',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.pinkAccent),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isEditMode ? 'Update' : 'Create',
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
