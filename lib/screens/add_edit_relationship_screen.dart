import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../database/db_helper.dart';
import '../models/person.dart';
import '../models/relationship.dart';
import '../models/relationship_image.dart';
import '../providers/person_provider.dart';

class AddEditRelationshipScreen extends StatefulWidget {
  final Person? fromPerson;
  final Relationship? relationship;

  const AddEditRelationshipScreen({
    super.key,
    this.fromPerson,
    this.relationship,
  });

  @override
  State<AddEditRelationshipScreen> createState() =>
      _AddEditRelationshipScreenState();
}

class _AddEditRelationshipScreenState extends State<AddEditRelationshipScreen> {
  Person? _selectedFrom;
  Person? _selectedTo;
  late final TextEditingController _labelController;
  bool _isMutual = false;
  final List<String> _imagePaths = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  bool get _isEditMode => widget.relationship != null;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(
      text: widget.relationship?.label ?? '',
    );
    _isMutual = widget.relationship?.isMutual ?? false;
    // fromPerson pre-select if provided
    _selectedFrom = widget.fromPerson;
    // If editing, we need to resolve persons after provider loads; handled in build
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _imagePaths.add(picked.path));
    }
  }

  void _removeImage(int index) {
    setState(() => _imagePaths.removeAt(index));
  }

  Future<void> _save() async {
    if (_selectedFrom == null || _selectedTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both persons')),
      );
      return;
    }
    if (_selectedFrom!.id == _selectedTo!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('From and To cannot be the same person')),
      );
      return;
    }
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Label must not be empty')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final provider = Provider.of<PersonProvider>(context, listen: false);
      final now = DateTime.now().toIso8601String();

      if (_isEditMode) {
        final updated = widget.relationship!.copyWith(
          fromPersonId: _selectedFrom!.id!,
          toPersonId: _selectedTo!.id!,
          label: label,
          isMutual: _isMutual,
        );
        await DbHelper.instance.updateRelationship(updated);
        // Images: insert newly added ones
        for (final path in _imagePaths) {
          await DbHelper.instance.insertRelationshipImage(
            RelationshipImage(relationshipId: updated.id!, imagePath: path),
          );
        }
        await provider.loadAll();
      } else {
        final rel = Relationship(
          fromPersonId: _selectedFrom!.id!,
          toPersonId: _selectedTo!.id!,
          label: label,
          isMutual: _isMutual,
          createdAt: now,
        );
        final newId = await DbHelper.instance.insertRelationship(rel);
        // Insert images attached to the relationship
        // Note: insertRelationship may return existing reverseId if mutual logic kicked in
        final effectiveId = newId;
        for (final path in _imagePaths) {
          await DbHelper.instance.insertRelationshipImage(
            RelationshipImage(relationshipId: effectiveId, imagePath: path),
          );
        }
        await provider.loadAll();
      }

      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildImageRow() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _imagePaths.length + 1,
        itemBuilder: (context, index) {
          if (index == _imagePaths.length) {
            return GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.add_a_photo, color: Colors.white54),
              ),
            );
          }
          final path = _imagePaths[index];
          return GestureDetector(
            onTap: () => _removeImage(index),
            child: Container(
              width: 80,
              height: 80,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: FileImage(File(path)),
                  fit: BoxFit.cover,
                  onError: (_, _) {},
                ),
                color: Colors.grey[900],
              ),
              child: const Align(
                alignment: Alignment.topRight,
                child: Icon(Icons.close, size: 18, color: Colors.white),
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
        title: Text(
          _isEditMode ? 'Edit Relationship' : 'Add Relationship',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Consumer<PersonProvider>(
        builder: (context, provider, _) {
          final persons = provider.persons;

          // Resolve initial selected persons for edit mode if not yet set
          if (_isEditMode &&
              _selectedFrom == null &&
              _selectedTo == null &&
              persons.isNotEmpty) {
            try {
              _selectedFrom = persons.firstWhere(
                (p) => p.id == widget.relationship!.fromPersonId,
              );
              _selectedTo = persons.firstWhere(
                (p) => p.id == widget.relationship!.toPersonId,
              );
            } catch (_) {}
          } else if (widget.fromPerson != null && _selectedFrom == null) {
            // Ensure fromPerson reference matches provider instance
            try {
              _selectedFrom = persons.firstWhere(
                (p) => p.id == widget.fromPerson!.id,
              );
            } catch (_) {
              _selectedFrom = widget.fromPerson;
            }
          }

          if (persons.length < 2) {
            return const Center(
              child: Text(
                'Need at least 2 persons to create a relationship.',
                style: TextStyle(color: Colors.white38),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<Person>(
                  initialValue: _selectedFrom,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'From',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.pinkAccent),
                    ),
                  ),
                  items: persons
                      .map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedFrom = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Person>(
                  initialValue: _selectedTo,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'To',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.pinkAccent),
                    ),
                  ),
                  items: persons
                      .map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTo = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _labelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Label (e.g. Crush, Ex, Situationship)',
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
                SwitchListTile(
                  title: const Text(
                    'Mutual',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: _isMutual,
                  activeThumbColor: Colors.pinkAccent,
                  onChanged: (v) => setState(() => _isMutual = v),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Relationship Images (tap to remove, + to add)',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 8),
                _buildImageRow(),
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
          );
        },
      ),
    );
  }
}
