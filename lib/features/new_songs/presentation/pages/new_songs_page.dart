import 'package:flutter/material.dart';

/// 新歌速递 — new releases, grouped by platform and region.
class NewSongsPage extends StatelessWidget {
  const NewSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新歌速递')),
      body: const Center(child: Text('新歌速递建设中')),
    );
  }
}
