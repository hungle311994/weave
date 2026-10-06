/// A plan line the workflow tracks: an implementation task or a test case.
enum ChecklistItemKind { task, testCase }

/// Where an item stands, as reported by the implementer and the reviewer.
enum ChecklistItemStatus {
  pending,
  inProgress,

  /// The implementer reports it finished.
  done,

  /// The implementer reports it could not finish.
  notDone,

  /// The reviewer confirmed it.
  verified,

  /// The reviewer found it missing or wrong.
  needsChanges,
}

/// One task (`T1`) or test case (`TC1`) from the plan.
final class ChecklistItem {
  const ChecklistItem({required this.id, required this.kind, required this.title, this.status = ChecklistItemStatus.pending, this.note, this.implementedBy, this.reviewedBy});

  factory ChecklistItem.fromJson(Map<String, Object?> json) => ChecklistItem(
    id: json['id']! as String,
    kind: ChecklistItemKind.values.byName(json['kind']! as String),
    title: json['title']! as String,
    status: ChecklistItemStatus.values.byName(json['status']! as String),
    note: json['note'] as String?,
    implementedBy: json['implementedBy'] as String?,
    reviewedBy: json['reviewedBy'] as String?,
  );

  final String id;
  final ChecklistItemKind kind;
  final String title;
  final ChecklistItemStatus status;

  /// The latest explanation, e.g. why a test case is missing.
  final String? note;

  /// Agent IDs that worked on and reviewed the item.
  final String? implementedBy;
  final String? reviewedBy;

  ChecklistItem copyWith({ChecklistItemStatus? status, String? note, bool clearNote = false, String? implementedBy, String? reviewedBy}) => ChecklistItem(
    id: id,
    kind: kind,
    title: title,
    status: status ?? this.status,
    note: clearNote ? null : note ?? this.note,
    implementedBy: implementedBy ?? this.implementedBy,
    reviewedBy: reviewedBy ?? this.reviewedBy,
  );

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'kind': kind.name, 'title': title, 'status': status.name, 'note': note, 'implementedBy': implementedBy, 'reviewedBy': reviewedBy};
}

/// The plan's tasks and test cases with their current status.
final class WorkflowChecklist {
  WorkflowChecklist(List<ChecklistItem> items) : items = List<ChecklistItem>.unmodifiable(items);

  /// Reads `- [ ] T1: ...` and `- [ ] TC1: ...` lines from a plan; checkbox
  /// lines without an ID become numbered tasks.
  factory WorkflowChecklist.fromPlan(String plan) {
    final List<ChecklistItem> items = <ChecklistItem>[];
    final Set<String> seen = <String>{};
    int nextTask = 1;
    for (final String line in plan.split('\n')) {
      final RegExpMatch? match = _planLine.firstMatch(line);
      if (match == null) {
        continue;
      }
      final String text = match[1]!.trim();
      final RegExpMatch? withId = _idPrefix.firstMatch(text);
      String id;
      String title;
      if (withId != null) {
        id = withId[1]!.toUpperCase();
        title = withId[2]!.trim();
      } else {
        while (seen.contains('T$nextTask')) {
          nextTask++;
        }
        id = 'T$nextTask';
        title = text;
      }
      if (title.isEmpty || !seen.add(id)) {
        continue;
      }
      items.add(ChecklistItem(id: id, kind: id.startsWith('TC') ? ChecklistItemKind.testCase : ChecklistItemKind.task, title: title));
    }
    return WorkflowChecklist(items);
  }

  factory WorkflowChecklist.fromJson(List<Object?> json) => WorkflowChecklist(<ChecklistItem>[for (final Object? item in json) ChecklistItem.fromJson(item! as Map<String, Object?>)]);

  static final RegExp _planLine = RegExp(r'^\s*[-*+]\s*\[[ xX]\]\s*(.+)$');
  static final RegExp _idPrefix = RegExp(r'^\**(TC\d+|T\d+)\**\s*[:.)\-–—]\s*(.*)$', caseSensitive: false);

  /// One report per line; every class excludes `\n` so a line never
  /// swallows the next one.
  static final RegExp _reportLine = RegExp(r'^[^\w\n]*(TC\d+|T\d+)[^\w\n]*?[:\-–—][ \t]*(done|not done|skipped|blocked|ok|verified|covered|missing|needs changes|incomplete|wrong)\b[ \t:\-–—]*(.*)$', caseSensitive: false, multiLine: true);

  final List<ChecklistItem> items;

  bool get isEmpty => items.isEmpty;

  List<ChecklistItem> get tasks => <ChecklistItem>[
    for (final ChecklistItem item in items)
      if (item.kind == ChecklistItemKind.task) item,
  ];

  List<ChecklistItem> get testCases => <ChecklistItem>[
    for (final ChecklistItem item in items)
      if (item.kind == ChecklistItemKind.testCase) item,
  ];

  /// Items the reviewer flagged; approval is impossible while any remain.
  List<ChecklistItem> get needingChanges => <ChecklistItem>[
    for (final ChecklistItem item in items)
      if (item.status == ChecklistItemStatus.needsChanges) item,
  ];

  /// Marks open items as being worked on by [agentId].
  WorkflowChecklist start(String agentId) => WorkflowChecklist(<ChecklistItem>[
    for (final ChecklistItem item in items)
      if (item.status == ChecklistItemStatus.verified) item else item.copyWith(status: ChecklistItemStatus.inProgress, implementedBy: agentId),
  ]);

  /// Applies `T1: done` / `TC2: not done — reason` lines from the implementer.
  WorkflowChecklist applyImplementerReport(String report, String agentId) => _apply(report, (ChecklistItem item, String verdict, String note) {
    final bool finished = verdict == 'done' || verdict == 'ok' || verdict == 'verified' || verdict == 'covered';
    return item.copyWith(status: finished ? ChecklistItemStatus.done : ChecklistItemStatus.notDone, note: note.isEmpty ? null : note, clearNote: note.isEmpty, implementedBy: agentId);
  });

  /// Applies `T1: ok` / `TC2: missing — reason` lines from the reviewer.
  WorkflowChecklist applyReviewerReport(String report, String agentId) => _apply(report, (ChecklistItem item, String verdict, String note) {
    final bool accepted = verdict == 'ok' || verdict == 'verified' || verdict == 'covered' || verdict == 'done';
    return item.copyWith(status: accepted ? ChecklistItemStatus.verified : ChecklistItemStatus.needsChanges, note: note.isEmpty ? null : note, clearNote: note.isEmpty, reviewedBy: agentId);
  });

  WorkflowChecklist _apply(String report, ChecklistItem Function(ChecklistItem item, String verdict, String note) update) {
    final Map<String, (String, String)> reported = <String, (String, String)>{
      for (final RegExpMatch match in _reportLine.allMatches(report)) match[1]!.toUpperCase(): (match[2]!.toLowerCase(), match[3]!.trim()),
    };
    return WorkflowChecklist(<ChecklistItem>[
      for (final ChecklistItem item in items)
        if (reported[item.id] case (final String verdict, final String note)) update(item, verdict, note) else item,
    ]);
  }

  /// Markdown for prompts: every item with its status and note.
  String describe() => items.map((ChecklistItem item) => '- ${item.id} [${item.status.name}] ${item.title}${item.note == null ? '' : ' — ${item.note}'}').join('\n');

  List<Map<String, Object?>> toJson() => <Map<String, Object?>>[for (final ChecklistItem item in items) item.toJson()];
}
