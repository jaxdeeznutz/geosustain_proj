part of '../main.dart';

class MessageLogPage extends StatefulWidget {
  final ApiService api;
  const MessageLogPage({super.key, required this.api});
  @override
  State<MessageLogPage> createState() => _MessageLogPageState();
}

class _MessageLogPageState extends State<MessageLogPage> {
  int offset = 0;
  late Future<Map<String, dynamic>> data = fetch();
  Future<Map<String, dynamic>> fetch() =>
      widget.api.getRecordPage('/api/admin/messages', offset: offset);
  void load(int next) => setState(() {
    offset = next;
    data = fetch();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Push delivery log')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(friendlyErrorMessage(snapshot.error!)),
                TextButton(
                  onPressed: () => load(offset),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final value = snapshot.data!;
        final messages = value['messages'] as List;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${value['scope']}'),
            if (messages.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No deliveries for current subscriptions.'),
              ),
            ...messages.map(
              (row) => Card(
                child: ListTile(
                  title: Text('Message ${row['id']} · ${row['status']}'),
                  subtitle: Text(
                    'Analysis ${row['session_id']} · ${row['platform']}\nFailed attempts: ${row['attempts']}\nProvider accepted: ${row['provider_accepted_at'] ?? 'Not yet'}\nNext eligible attempt: ${row['next_attempt_at']}',
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: offset == 0
                      ? null
                      : () => load(math.max(0, offset - 50)),
                  child: const Text('Previous'),
                ),
                Text('Page ${offset ~/ 50 + 1}'),
                TextButton(
                  onPressed: value['has_more'] == true
                      ? () => load(offset + 50)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
