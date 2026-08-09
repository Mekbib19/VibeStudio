import '../services/server_service.dart';

enum AgentStatus { stopped, starting, idle, busy, error }

/// What a team member is responsible for.
enum AgentRole {
  /// Writes/edits application code (routes, models, controllers, ...).
  engineer,

  /// Verifies finished work: runs tests/checks and reports PASS or FAIL.
  /// It never picks up implementation todos on its own.
  tester,

  /// The "main" agent: stays alive, receives worker summaries and QA
  /// verdicts, and coordinates the team.
  coordinator,
}

extension AgentRoleLabel on AgentRole {
  String get label => switch (this) {
        AgentRole.engineer => 'engineer',
        AgentRole.tester => 'tester',
        AgentRole.coordinator => 'coordinator',
      };
}

extension AgentStatusLabel on AgentStatus {
  String get label => switch (this) {
        AgentStatus.stopped => 'stopped',
        AgentStatus.starting => 'starting',
        AgentStatus.idle => 'idle',
        AgentStatus.busy => 'working',
        AgentStatus.error => 'error',
      };
}

class AgentLogEntry {
  final DateTime time;
  final String text;
  final bool isError;

  AgentLogEntry(this.text, {this.isError = false, DateTime? time})
      : time = time ?? DateTime.now();
}

class Agent {
  final String id;
  final String name;
  final AgentRole role;

  /// The "main" AI of the team. It stays alive, receives a summary from every
  /// worker agent, and is never auto-shut down.
  bool isMain;

  /// Spawned by the app's auto team (see AppController.autoTeam): the app
  /// tops these workers up to a small cap when todos are queued and retires
  /// them again when the queue drains, so it can manage them on its own.
  final bool autoManaged;
  String? sessionId;
  AgentStatus status;

  /// The opencode server this agent talks to. The main AI uses the shared
  /// Vibe Studio server (null here); workers own a short-lived server per
  /// job that stops and returns to the free buffer when the job finishes.
  ServerService? server;

  String? currentTask;
  String? currentTaskId;
  int? taskStartedAt;
  int? lastStallWarnAt;
  String? lastError;
  final List<AgentLogEntry> log;
  int tasksCompleted;

  Agent({
    required this.id,
    required this.name,
    required this.role,
    this.isMain = false,
    this.autoManaged = false,
    this.sessionId,
    this.status = AgentStatus.stopped,
    this.server,
    this.currentTask,
    this.currentTaskId,
    this.taskStartedAt,
    this.lastStallWarnAt,
    this.lastError,
    List<AgentLogEntry>? log,
    this.tasksCompleted = 0,
  }) : log = log ?? [];

  bool get busy => status == AgentStatus.busy || status == AgentStatus.starting;

  void logLine(String text, {bool isError = false}) {
    log.add(AgentLogEntry(text, isError: isError));
    if (log.length > 500) log.removeRange(0, log.length - 500);
  }
}

class SystemLogEntry {
  final DateTime time;
  final String text;
  final bool isError;

  SystemLogEntry(this.text, {this.isError = false, DateTime? time})
      : time = time ?? DateTime.now();
}
