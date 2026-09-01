import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../models/person.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Person> _results = [];
  bool _hasSearched = false;

  Future<void> _onQueryChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    final results = await DbHelper.instance.searchPersons(query);
    if (!mounted) return;
    setState(() {
      _results = results;
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
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search by name or personality...',
            hintStyle: TextStyle(color: Colors.white38),
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_hasSearched && _controller.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search persons',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'No results found.',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final person = _results[index];
        final isAsset = person.imagePath.startsWith('assets/');
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: isAsset
                ? AssetImage(person.imagePath)
                : FileImage(File(person.imagePath)) as ImageProvider,
            backgroundColor: Colors.grey[800],
            onBackgroundImageError: (_, _) {},
          ),
          title: Text(person.name, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            person.personality,
            style: const TextStyle(color: Colors.white60),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfileScreen(person: person)),
          ),
        );
      },
    );
  }
}
