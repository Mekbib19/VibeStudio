import 'package:flutter/material.dart';

import '../models/agent.dart';
import '../state/app_controller.dart';

class AgentPanel extends StatefulWidget {
  final AppController controller;

  const AgentPanel(this.controller, {super.key});

  @override
  State<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends State<AgentPanel> {
  final _mission = TextEditingController();
  String _missionStatus = '';

  @override
  void dispose() {
    _mission.dispose();
    super.dispose();
  }

  Future<void> _sendMission() async {
    final ok = await widget.controller.sendToMain(_mission.text);
    if (!ok) {
      setState(() => _missionStatus = 'Set a main agent first (★).');
      return;
    }
    _mission.clear();
    setState(() => _missionStatus = '');
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final hasMain = controller.mainAgent != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'AI Team',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${controller.agents.where((a) => a.status != AgentStatus.stopped).length} active',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              Text(
                '${controller.freeBufferCount} free server',
                style: TextStyle(
                  fontSize: 11,
                  color: controller.freeBufferCount > 0
                      ? Colors.tealAccent
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.agents.isEmpty
              ? const Center(
                  child: Text(
                    'No agents yet.\nThe auto team spawns up to 3 workers\nwhen tasks are queued — or add one\nmanually with "Add Agent".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: controller.agents.length,
                  itemBuilder: (context, i) => _AgentCard(
                    agent: controller.agents[i],
                    controller: controller,
                  ),
                ),
        ),
        if (hasMain) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _mission,
                  onSubmitted: (_) => _sendMission(),
                  maxLines: 2,
                  minLines: 1,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText:
                        'Tell the main AI what to do…\ne.g. "UI is broken and server error"',
                    isDense: true,
                    contentPadding: const EdgeInsets.all(8),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, size: 16),
                      onPressed: _sendMission,
                      tooltip: 'Send mission to the main AI',
                    ),
                  ),
                ),
                if (_missionStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _missionStatus,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.orangeAccent),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Agent agent;
  final AppController controller;

  const _AgentCard({required this.agent, required this.controller});

  @override
  Widget build(BuildContext context) {
    final color = switch (agent.status) {
      AgentStatus.busy => Colors.blueAccent,
      AgentStatus.idle => Colors.greenAccent,
      AgentStatus.starting => Colors.amber,
      AgentStatus.stopped => Colors.grey,
      AgentStatus.error => Colors.redAccent,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: const Color(0xFF1E1F26),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    agent.isMain ? '★ ${agent.name}' : agent.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => controller.setMainAgent(agent),
                  icon: Icon(
                    agent.isMain ? Icons.star : Icons.star_border,
                    size: 18,
                    color: agent.isMain ? Colors.amber : Colors.grey,
                  ),
                  tooltip: agent.isMain
                      ? 'Main agent (orchestrator)'
                      : 'Set as main agent',
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  agent.status.label,
                  style: TextStyle(color: color, fontSize: 11),
                ),
                IconButton(
                  onPressed: agent.status == AgentStatus.stopped
                      ? () => controller.startAgent(agent)
                      : () => controller.stopAgent(agent),
                  icon: Icon(
                    agent.status == AgentStatus.stopped
                        ? Icons.play_arrow
                        : Icons.stop,
                    size: 17,
                  ),
                  tooltip: agent.status == AgentStatus.stopped
                      ? 'Start agent'
                      : 'Stop agent',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Text(
                    agent.role.label,
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.4,
                      color: Colors.grey,
                    ),
                  ),
                  if (agent.autoManaged) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2B33),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'AUTO',
                        style: TextStyle(
                          fontSize: 8.5,
                          letterSpacing: 0.5,
                          color: Colors.tealAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (agent.currentTask != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  agent.currentTask!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
              ),
            if (agent.tasksCompleted > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${agent.tasksCompleted} tasks completed',
                  style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 6),
            Container(
              height: 64,
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF14151A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: agent.log.isEmpty
                  ? const Text(
                      'no activity yet',
                      style: TextStyle(color: Colors.grey, fontSize: 10.5),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: agent.log.length,
                      itemBuilder: (context, i) {
                        final e = agent.log[agent.log.length - 1 - i];
                        return Text(
                          e.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: e.isError
                                ? Colors.redAccent.shade200
                                : Colors.white60,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
