import 'dart:io';

import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../models/person.dart';
import '../theme/app_colors.dart';

Future<Person?> showSearchBottomSheet(BuildContext context) {
  return showModalBottomSheet<Person>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.56,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      expand: false,
      snap: true,
      snapSizes: const [0.56, 0.92],
      builder: (_, scrollController) => _SearchSheetContent(scrollController: scrollController),
    ),
  );
}

class _SearchSheetContent extends StatefulWidget {
  final ScrollController scrollController;
  const _SearchSheetContent({required this.scrollController});

  @override
  State<_SearchSheetContent> createState() => _SearchSheetContentState();
}

class _SearchSheetContentState extends State<_SearchSheetContent> {
  final TextEditingController _controller = TextEditingController();
  List<Person> _results = [];
  bool _hasSearched = false;

  Future<void> _onChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    final res = await DbHelper.instance.searchPersons(query);
    if (!mounted) return;
    setState(() {
      _results = res;
      _hasSearched = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          // Search bar -- white rounded rectangle + red icon as in mock
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.black87, fontSize: 13),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        hintText: 'Search by name or personality...',
                        hintStyle: TextStyle(color: Colors.black38, fontSize: 12),
                      ),
                      onChanged: _onChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _onChanged(_controller.text),
                  child: const Icon(Icons.search, color: Colors.white, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Results – scrollable, driven by sheet controller when sheet expands
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // Use NestedScroll: outer sheet controller + inner ListView
    // Simpler: use SingleChildScrollView with same controller and inner ListView as Sliver
    if (!_hasSearched && _controller.text.isEmpty) {
      return ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('Type to search persons', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
            ),
          ),
        ],
      );
    }
    if (_results.isEmpty) {
      return ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('No results found.', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final p = _results[i];
        final isAsset = p.imagePath.startsWith('assets/');
        return GestureDetector(
          onTap: () {
            // Exit sheet first, then present profile (per request)
            Navigator.pop(context, p);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: isAsset
                      ? AssetImage(p.imagePath)
                      : FileImage(File(p.imagePath)) as ImageProvider,
                  backgroundColor: Colors.white,
                  onBackgroundImageError: (_, _) {},
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}
