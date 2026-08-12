import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../state/app_controller.dart';

class TodoPanel extends StatelessWidget {
  final AppController controller;

  const TodoPanel(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final items = controller.todoItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Shared Todo List',
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
                '${items.where((t) => t.status == TodoStatus.done).length}/${items.length} done',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              IconButton(
                onPressed: () => _addTodo(context),
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Add todo',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'No todos yet.\nAdd one and agents will pick it up.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _TodoTile(
                    item: items[i],
                    controller: controller,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _addTodo(BuildContext context) async {
    final titleC = TextEditingController();
    final descC = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New todo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleC,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descC,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (titleC.text.trim().isEmpty) return;
              controller.addTodo(titleC.text.trim(), descC.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    titleC.dispose();
    descC.dispose();
  }
}

class _TodoTile extends StatelessWidget {
  final TodoItem item;
  final AppController controller;

  const _TodoTile({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final color = switch (item.status) {
      TodoStatus.done => Colors.greenAccent,
      TodoStatus.inProgress => Colors.blueAccent,
      TodoStatus.todo => Colors.grey,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 5),
      color: const Color(0xFF1E1F26),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => controller.updateTodo(
                item.copyWith(
                  status: item.status == TodoStatus.done
                      ? TodoStatus.todo
                      : TodoStatus.done,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  item.status == TodoStatus.done
                      ? Icons.check_circle
                      : item.status == TodoStatus.inProgress
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                  size: 18,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  if (item.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ),
                  if (item.assignee != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '↦ ${item.assignee}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: color,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => controller.deleteTodo(item.id),
              icon: const Icon(Icons.delete_outline, size: 15),
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}
