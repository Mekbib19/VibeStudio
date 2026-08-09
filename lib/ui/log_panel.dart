import 'package:flutter/material.dart';

import '../state/app_controller.dart';

class LogPanel extends StatelessWidget {
  final AppController controller;

  const LogPanel(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              const Text(
                'System Log',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => controller.systemLog.clear(),
                icon: const Icon(Icons.clear_all, size: 16),
                tooltip: 'Clear log',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.systemLog.isEmpty
              ? const Center(
                  child: Text(
                    'no log entries',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: controller.systemLog.length,
                  itemBuilder: (context, i) {
                    final e = controller.systemLog[i];
                    final hh = e.time.hour.toString().padLeft(2, '0');
                    final mm = e.time.minute.toString().padLeft(2, '0');
                    final ss = e.time.second.toString().padLeft(2, '0');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '[$hh:$mm:$ss] ${e.text}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: e.isError
                              ? Colors.redAccent.shade200
                              : Colors.white60,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
