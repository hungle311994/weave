/// The reviewer's decision, read from the final `VERDICT:` line.
enum ReviewVerdict { approved, changesRequested, missing }

/// Reads the last `VERDICT: APPROVED` or `VERDICT: CHANGES_REQUESTED` line.
ReviewVerdict parseReviewVerdict(String review) {
  final List<RegExpMatch> matches = _verdictPattern.allMatches(review).toList();
  if (matches.isEmpty) {
    return ReviewVerdict.missing;
  }
  return matches.last.group(1)!.toUpperCase() == 'APPROVED' ? ReviewVerdict.approved : ReviewVerdict.changesRequested;
}

final RegExp _verdictPattern = RegExp(r'^\W*VERDICT\W*:\W*(APPROVED|CHANGES_REQUESTED)\b', caseSensitive: false, multiLine: true);

/// Everything a prompt may refer to; fields are filled as phases complete.
final class WorkflowPromptContext {
  const WorkflowPromptContext({
    required this.request,
    required this.repositoryRoot,
    required this.reviewCycle,
    this.plan,
    this.planFeedback,
    this.checklist,
    this.implementationSummary,
    this.reviewFeedback,
    this.verificationReport,
    this.diff,
    this.isDiffTruncated = false,
  });

  final String request;
  final String repositoryRoot;
  final int reviewCycle;
  final String? plan;

  /// Why the previous plan must change, from the reviewer or the user.
  final String? planFeedback;

  /// Tasks and test cases with their status, one per line.
  final String? checklist;
  final String? implementationSummary;
  final String? reviewFeedback;
  final String? verificationReport;
  final String? diff;
  final bool isDiffTruncated;
}

/// Builds the instructions sent to each role; replaceable per installation.
abstract interface class WorkflowPrompts {
  String planner(WorkflowPromptContext context);

  /// The reviewer critiques a plan before any code changes.
  String planReview(WorkflowPromptContext context);

  String implementer(WorkflowPromptContext context);

  String selfReview(WorkflowPromptContext context);

  String reviewer(WorkflowPromptContext context);
}

/// Provider-neutral prompts that work with any coding agent.
///
/// They stay short to save tokens, and ask for machine-readable lines
/// (`T1: done`, `TC2: missing — ...`, `VERDICT: ...`) that Weave parses.
final class DefaultWorkflowPrompts implements WorkflowPrompts {
  const DefaultWorkflowPrompts();

  static const String _sharedRules = '''
Rules:
- Work only inside the repository at the path above.
- Never commit, push, merge, rebase, reset, checkout, stash, or create branches or worktrees.
- Do not create planning, notes, or handoff files in the repository; Weave stores those outside it.
- Never print secrets, tokens, or credentials.''';

  static const String _planFormat = '''
Format the plan as Markdown with exactly these sections:
## Tasks
- [ ] T1: <one concrete change per line, in order>
## Test cases
- [ ] TC1: <given / when / then for one behavior>
Cover the main path, edge cases, invalid input and errors, and regressions of existing behavior with test cases; every task needs at least one.''';

  @override
  String planner(WorkflowPromptContext context) {
    final StringBuffer prompt = StringBuffer()
      ..writeln('You are the planner in a Weave workflow. Another agent will implement your plan and a third will review it.')
      ..writeln()
      ..writeln('Repository: ${context.repositoryRoot}')
      ..writeln()
      ..writeln('Request:')
      ..writeln(context.request);
    if (context.planFeedback case final String feedback) {
      prompt
        ..writeln()
        ..writeln('Revise your previous plan. Feedback to address:')
        ..writeln(feedback)
        ..writeln()
        ..writeln('Previous plan:')
        ..writeln(context.plan ?? '(none)');
    }
    prompt
      ..writeln()
      ..writeln(_sharedRules)
      ..writeln('- You are read-only: inspect the code but do not modify any file.')
      ..writeln()
      ..writeln('Reply with a concise implementation plan: the files to change, edge cases, and how to verify the change.')
      ..write(_planFormat);
    return prompt.toString();
  }

  @override
  String planReview(WorkflowPromptContext context) =>
      '''
You are the plan reviewer in a Weave workflow. Check the plan below before any code is written.

Repository: ${context.repositoryRoot}

Request:
${context.request}

Plan:
${context.plan ?? '(no plan)'}

$_sharedRules
- You are read-only: inspect the code but do not modify any file.

Check that the tasks fully solve the request, fit the existing code, and that the test cases cover the main path, edge cases, errors, and regressions. List every missing task or test case.
End your reply with exactly one line: "VERDICT: APPROVED" or "VERDICT: CHANGES_REQUESTED".''';

  @override
  String implementer(WorkflowPromptContext context) {
    final StringBuffer prompt = StringBuffer()
      ..writeln('You are the implementer in a Weave workflow.')
      ..writeln()
      ..writeln('Repository: ${context.repositoryRoot}')
      ..writeln()
      ..writeln('Request:')
      ..writeln(context.request)
      ..writeln()
      ..writeln('Plan:')
      ..writeln(context.plan ?? '(no plan)');
    if (context.checklist case final String checklist when checklist.isNotEmpty) {
      prompt
        ..writeln()
        ..writeln('Checklist (status per item):')
        ..writeln(checklist);
    }
    if (context.reviewFeedback case final String feedback) {
      prompt
        ..writeln()
        ..writeln('The reviewer requested changes (review round ${context.reviewCycle}). Address every point:')
        ..writeln(feedback);
    }
    if (context.verificationReport case final String report) {
      prompt
        ..writeln()
        ..writeln('Verification results:')
        ..writeln(report);
    }
    prompt
      ..writeln()
      ..writeln(_sharedRules)
      ..writeln()
      ..writeln('Edit the files needed to complete the request and write an automated test for every test case (TC). Keep changes focused on the plan.')
      ..write('Reply with a short summary of what you changed, then one line per checklist item: "T1: done" or "T1: not done — <reason>".');
    return prompt.toString();
  }

  @override
  String selfReview(WorkflowPromptContext context) {
    final String checklist = context.checklist == null || context.checklist!.isEmpty ? '' : '\nChecklist:\n${context.checklist}\n';
    return '''
Review the changes you just made against the request and the plan before handing them to the reviewer.

Request:
${context.request}

Plan:
${context.plan ?? '(no plan)'}
$checklist
Fix any bug, missing piece, missing test, or inconsistency you find directly in the files.

$_sharedRules

Reply with a short summary of the final state of your changes, then one line per checklist item: "T1: done" or "T1: not done — <reason>".''';
  }

  @override
  String reviewer(WorkflowPromptContext context) {
    final String diff = (context.diff ?? '').trim();
    final String checklist = context.checklist == null || context.checklist!.isEmpty ? '' : '\nChecklist:\n${context.checklist}\n';
    return '''
You are the reviewer in a Weave workflow. Review the uncommitted changes in the repository.

Repository: ${context.repositoryRoot}

Request:
${context.request}

Plan:
${context.plan ?? '(no plan)'}
$checklist
Implementer summary:
${context.implementationSummary ?? '(no summary)'}

Verification results (run by Weave):
${context.verificationReport ?? 'Not run.'}

Diff${context.isDiffTruncated ? ' (truncated; read the files for the rest)' : ''}:
${diff.isEmpty ? '(no changes)' : '```diff\n$diff\n```'}

$_sharedRules
- You are read-only: inspect the code but do not modify any file.

Check correctness, completeness against the request, security, and tests. For every test case, confirm a test exercises it. List every required change.
Then write one line per checklist item: "T1: ok" or "T1: needs changes — <reason>", and "TC1: covered" or "TC1: missing — <reason>".
End your reply with exactly one line: "VERDICT: APPROVED" or "VERDICT: CHANGES_REQUESTED".''';
  }
}
