part of '../climbing_map.dart';

/// Keeps a place (an area, a sector, a boulder) on the device for days
/// without signal (#459): "Download for offline", then "Saved offline" with
/// Update and Remove.
class OfflineButton extends StatefulWidget {
  const OfflineButton({super.key, required this.editor, required this.placeId, this.compact = false});
  final PlaceEditor editor;
  final String placeId;

  /// An icon for an app bar instead of a labelled button.
  final bool compact;

  @override
  State<OfflineButton> createState() => _OfflineButtonState();
}

class _OfflineButtonState extends State<OfflineButton> {
  (int, int)? _progress;

  Future<void> _download() async {
    setState(() => _progress = (0, 0));
    final err = await widget.editor.keepOffline(widget.placeId, progress: (d, n) => mounted ? setState(() => _progress = (d, n)) : null);
    if (!mounted) return;
    setState(() => _progress = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Saved: this place now opens without signal.')));
  }

  Future<void> _menu() async {
    final a = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Saved offline'),
              subtitle: Text('Its sections and photos are on this phone. New sections are fetched when you have signal.'),
            ),
            ListTile(leading: const Icon(Icons.refresh), title: const Text('Update now'), onTap: () => Navigator.pop(context, 'update')),
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remove from this phone'), onTap: () => Navigator.pop(context, 'remove')),
          ],
        ),
      ),
    );
    if (!mounted || a == null) return;
    if (a == 'update') return _download();
    await widget.editor.forgetOffline(widget.placeId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.editor.canKeepOffline) return const SizedBox.shrink();
    final p = _progress;
    if (widget.compact) {
      if (p != null) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, value: p.$2 == 0 ? null : p.$1 / p.$2)),
        );
      }
      return widget.editor.isOffline(widget.placeId)
          ? IconButton(tooltip: 'Saved offline', onPressed: _menu, icon: const Icon(Icons.offline_pin))
          : IconButton(tooltip: 'Download for offline', onPressed: _download, icon: const Icon(Icons.download_for_offline_outlined));
    }
    if (p != null) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        label: Text(p.$2 == 0 ? 'Downloading…' : 'Downloading ${p.$1}/${p.$2} photos'),
      );
    }
    if (widget.editor.isOffline(widget.placeId)) {
      return OutlinedButton.icon(onPressed: _menu, icon: const Icon(Icons.offline_pin), label: const Text('Saved offline'));
    }
    return FilledButton.tonalIcon(onPressed: _download, icon: const Icon(Icons.download_for_offline_outlined), label: const Text('Download for offline'));
  }
}
