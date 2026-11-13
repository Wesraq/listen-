import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../data/content_models.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';

Future<void> openContentNotesSheet(
  BuildContext context, {
  required String titleId,
  required String locationId,
  required String anchor,
  required double position,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ContentNotesSheet(
      titleId: titleId,
      locationId: locationId,
      anchor: anchor,
      position: position,
    ),
  );
}

class ContentNotesSheet extends StatefulWidget {
  const ContentNotesSheet({
    super.key,
    required this.titleId,
    required this.locationId,
    required this.anchor,
    required this.position,
  });

  final String titleId;
  final String locationId;
  final String anchor;
  final double position;

  @override
  State<ContentNotesSheet> createState() => _ContentNotesSheetState();
}

class _ContentNotesSheetState extends State<ContentNotesSheet> {
  final textController = TextEditingController();
  bool recording = false;
  int elapsedSec = 0;
  Timer? tick;
  String? activePath;

  @override
  void dispose() {
    tick?.cancel();
    textController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (recording) {
      tick?.cancel();
      setState(() => recording = false);
      return;
    }

    // Prototype voice clip: copy bundled narration audio into a note file.
    // Caps at 60 seconds of "recording" time for the product rule.
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    final bytes = await rootBundle.load('assets/audio/sample_narration.wav');
    await File(path).writeAsBytes(bytes.buffer.asUint8List());

    setState(() {
      recording = true;
      elapsedSec = 0;
      activePath = path;
    });
    tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => elapsedSec++);
      if (elapsedSec >= 60) {
        timer.cancel();
        setState(() => recording = false);
      }
    });
  }

  Future<void> _saveText(SessionState session) async {
    final text = textController.text.trim();
    if (text.isEmpty) return;
    await session.addContentNote(
      ContentNote(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        titleId: widget.titleId,
        kind: 'text',
        anchor: widget.anchor,
        locationId: widget.locationId,
        position: widget.position,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        text: text,
      ),
    );
    textController.clear();
  }

  Future<void> _saveVoice(SessionState session) async {
    final path = activePath;
    if (path == null || !File(path).existsSync() || elapsedSec <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record a short voice note first (up to 60 seconds).')),
      );
      return;
    }
    await session.addContentNote(
      ContentNote(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        titleId: widget.titleId,
        kind: 'voice',
        anchor: widget.anchor,
        locationId: widget.locationId,
        position: widget.position,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        voicePath: path,
        voiceDurationSec: elapsedSec.toDouble().clamp(1, 60),
        text: 'Voice note · $elapsedSec sec',
      ),
    );
    setState(() {
      activePath = null;
      elapsedSec = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final items = session.notesFor(widget.titleId);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Notes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            widget.anchor == 'audio'
                ? 'Saved to this moment in the audio'
                : 'Saved to this place in the chapter',
            style: TextStyle(color: ListenColors.ink.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: textController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Write a note',
              hintText: 'A thought, quote, or reminder…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(onPressed: () => _saveText(session), child: const Text('Save note')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _toggleRecord,
                icon: Icon(recording ? Icons.stop : Icons.mic),
                label: Text(recording ? 'Stop (${elapsedSec}s)' : 'Record voice'),
              ),
              const SizedBox(width: 8),
              if (!recording && activePath != null)
                TextButton(onPressed: () => _saveVoice(session), child: const Text('Save voice')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Voice notes can be up to 60 seconds and stay attached to this spot.',
            style: TextStyle(fontSize: 12, color: ListenColors.ink.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          Text('Your notes here', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No notes yet — add one while you read or listen.'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final note = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(note.kind == 'voice' ? Icons.graphic_eq : Icons.notes),
                    title: Text(note.text ?? 'Voice note'),
                    subtitle: Text(note.anchorLabel),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => session.removeContentNote(note.id),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
