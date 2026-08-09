import 'dart:convert';

enum TodoStatus {
  todo,
  inProgress,
  done;

  static TodoStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return TodoStatus.inProgress;
      case 'done':
        return TodoStatus.done;
      default:
        return TodoStatus.todo;
    }
  }

  String get wire => switch (this) {
        TodoStatus.todo => 'todo',
        TodoStatus.inProgress => 'in_progress',
        TodoStatus.done => 'done',
      };

  String get label => switch (this) {
        TodoStatus.todo => 'todo',
        TodoStatus.inProgress => 'in progress',
        TodoStatus.done => 'done',
      };
}

class TodoItem {
  final String id;
  String title;
  String description;
  TodoStatus status;
  String? assignee;
  final int createdAt;
  int updatedAt;

  TodoItem({
    required this.id,
    required this.title,
    this.description = '',
    this.status = TodoStatus.todo,
    this.assignee,
    int? createdAt,
    int? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.wire,
        if (assignee != null) 'assignee': assignee,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        id: json['id'] as String,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        status: TodoStatus.fromString(json['status'] as String?),
        assignee: json['assignee'] as String?,
        createdAt: (json['created_at'] as num?)?.toInt(),
        updatedAt: (json['updated_at'] as num?)?.toInt(),
      );

  TodoItem copyWith({
    String? title,
    String? description,
    TodoStatus? status,
    String? assignee,
  }) =>
      TodoItem(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        status: status ?? this.status,
        assignee: assignee ?? this.assignee,
        createdAt: createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
}

class TodoLedger {
  final int version;
  final List<TodoItem> todos;

  const TodoLedger({this.version = 1, required this.todos});

  Map<String, dynamic> toJson() => {
        'version': version,
        'todos': todos.map((t) => t.toJson()).toList(),
      };

  factory TodoLedger.fromJson(Map<String, dynamic> json) => TodoLedger(
        version: (json['version'] as num?)?.toInt() ?? 1,
        todos: ((json['todos'] as List?) ?? [])
            .map((e) => TodoItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

String todoLedgerToJson(TodoLedger ledger) =>
    const JsonEncoder.withIndent('  ').convert(ledger.toJson());
