// The upload state in the app bar (#460): a cloud with a count while changes
// wait, and a sheet to send them now or choose Wi-Fi only.
import 'package:flutter/material.dart';

import 'shared_places.dart';

class UploadButton extends StatelessWidget {
  const UploadButton({super.key, required this.places});
  final SharedPlaces places;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([places, places.outbox]),
    builder: (context, _) {
      final n = places.outbox.ops.length;
      return IconButton(
        tooltip: n == 0 ? 'Everything is uploaded' : '$n waiting to upload',
        onPressed: () => _sheet(context),
        icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(n == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined)),
      );
    },
  );

  void _sheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: places.outbox,
      builder: (context, _) {
        final o = places.outbox, n = o.ops.length;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(n == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined),
                title: Text(
                  n == 0
                      ? 'Everything is uploaded'
                      : n == 1
                      ? '1 change waits to upload'
                      : '$n changes wait to upload',
                ),
                subtitle: const Text('Logs, votes, comments and new routes are saved on this phone first, and upload when there is signal.'),
              ),
              if (o.refused != null) ListTile(leading: const Icon(Icons.error_outline), title: Text(o.refused!)),
              SwitchListTile(
                title: const Text('Upload only on Wi-Fi'),
                subtitle: const Text('Saves mobile data; changes wait until you are on Wi-Fi.'),
                value: o.wifiOnly,
                onChanged: o.setWifiOnly,
              ),
              if (n > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: FilledButton.icon(
                    onPressed: () async {
                      final err = await places.send();
                      if (!context.mounted) return;
                      final left = places.outbox.ops.length;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(err ?? (left == 0 ? 'All uploaded.' : 'No signal yet; $left still waiting.'))));
                    },
                    icon: const Icon(Icons.upload),
                    label: const Text('Upload now'),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
