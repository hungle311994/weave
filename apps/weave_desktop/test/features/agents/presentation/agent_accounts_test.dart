import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave/features/agents/domain/agents_repository.dart';
import 'package:weave/features/agents/presentation/agents_controller.dart';
import 'package:weave/features/agents/presentation/agents_page.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';

String _done(AgentRunRequest request, ScriptedAgentSession session) => 'done';

/// Agents and accounts in memory; Terminal commands are recorded.
final class _FakeAgentsRepository implements AgentsRepository {
  _FakeAgentsRepository(this.agents);

  @override
  List<AgentAdapter> agents;

  final List<String> terminal = <String>[];
  final List<String> removedAccounts = <String>[];

  @override
  String get configurationPath => '/tmp/agents.json';

  @override
  Future<List<AgentAvailability>> checkAvailability() => Future.wait(<Future<AgentAvailability>>[for (final AgentAdapter adapter in agents) adapter.checkAvailability()]);

  @override
  Future<AgentPlanUsage> readPlanUsage(String agentId) => agents.firstWhere((AgentAdapter adapter) => adapter.id == agentId).readPlanUsage();

  @override
  Future<Set<String>> customAgentIds() async => const <String>{};

  @override
  Future<void> saveAgent(AgentDefinition definition) => throw UnimplementedError();

  @override
  Future<void> removeAgent(String agentId) => throw UnimplementedError();

  @override
  Future<AgentAccount> addAccount(String agentId, String name) async {
    final AgentAccount account = AgentAccount(id: '$agentId-${name.toLowerCase()}', agentId: agentId, name: name);
    agents = <AgentAdapter>[
      ...agents,
      ScriptedAgentAdapter(id: account.id, displayName: 'Claude Like · $name', handler: _done, isAvailable: false, signInCommand: "CONFIG='/weave/accounts/${account.id}' claude auth login", account: account),
    ];
    return account;
  }

  @override
  Future<void> removeAccount(String accountId) async {
    removedAccounts.add(accountId);
    agents = <AgentAdapter>[
      for (final AgentAdapter adapter in agents)
        if (adapter.id != accountId) adapter,
    ];
  }

  @override
  Future<AgentAccountInfo?> readAccount(String agentId) => agents.firstWhere((AgentAdapter adapter) => adapter.id == agentId).readAccount();

  @override
  Future<void> openInTerminal(String command, {required String name}) async => terminal.add(command);

  @override
  Future<bool> isInstalled(String executable) async => false;
}

void main() {
  late _FakeAgentsRepository repository;
  late AgentsController controller;

  setUp(() {
    repository = _FakeAgentsRepository(<AgentAdapter>[
      ScriptedAgentAdapter(
        id: 'claude',
        displayName: 'Claude Like',
        handler: _done,
        supportsAccounts: true,
        accountInfo: const AgentAccountInfo(email: 'a@example.com', plan: 'team'),
      ),
      ScriptedAgentAdapter(id: 'plain', displayName: 'Plain Agent', handler: _done),
      ScriptedAgentAdapter(
        id: 'claude-personal',
        displayName: 'Claude Like · Personal',
        handler: _done,
        account: AgentAccount(id: 'claude-personal', agentId: 'claude', name: 'Personal'),
        accountInfo: const AgentAccountInfo(email: 'b@example.com', plan: 'max'),
      ),
    ]);
    controller = AgentsController(repository);
  });
  tearDown(() => controller.dispose());

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeaveTheme.dark(),
        home: Scaffold(
          // The app shell rebuilds the page when the controller changes.
          body: ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? _) => AgentsPage(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cards show who each account is signed in as, extra accounts follow their agent', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.text('a@example.com'), findsOneWidget, reason: 'the email has a line of its own, so a long one is not cut short by the plan');
    expect(find.text('b@example.com'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('agent-vendor-claude'))).data, 'claude · Team');
    expect(tester.widget<Text>(find.byKey(const Key('agent-vendor-claude-personal'))).data, 'claude-personal · Max', reason: 'scripted agents have no vendor, so the ID stands in');
    expect(find.byKey(const Key('agent-account-plain')), findsNothing, reason: 'an agent that reports no account shows no account line');
    expect(controller.agents.map((AgentAdapter adapter) => adapter.id), <String>['claude', 'claude-personal', 'plain']);
    expect(tester.getTopLeft(find.byKey(const ValueKey<String>('agent-card-claude-personal'))).dx, greaterThan(tester.getTopLeft(find.byKey(const ValueKey<String>('agent-card-claude'))).dx), reason: 'next to its agent in the grid');

    expect(find.byKey(const Key('add-account-claude')), findsOneWidget);
    expect(find.byKey(const Key('add-account-plain')), findsNothing, reason: 'the agent has no configuration folder variable');
    expect(find.byKey(const Key('add-account-claude-personal')), findsNothing, reason: 'an account cannot have accounts');
    expect(find.byKey(const Key('remove-account-claude-personal')), findsOneWidget);
    expect(find.byKey(const Key('remove-account-claude')), findsNothing, reason: 'the default sign-in is not removable');
  });

  testWidgets('Add account names the account, then opens its own sign-in in Terminal', (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('add-account-claude')));
    await tester.pumpAndSettle();
    expect(find.text('Add Claude Like account'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-account')));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(WeaveToast), matching: find.textContaining('Name the account')),
      findsOneWidget,
      reason: 'a name is required',
    );
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await tester.enterText(find.byKey(const Key('account-name')), 'Work');
    await tester.tap(find.byKey(const Key('save-account')));
    await tester.pumpAndSettle();

    expect(repository.terminal, <String>["CONFIG='/weave/accounts/claude-work' claude auth login"]);
    expect(find.byKey(const ValueKey<String>('agent-card-claude-work')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('agent-card-claude-work')), matching: find.text('Not signed in')), findsOneWidget);
    expect(find.textContaining('in the Terminal window that opened'), findsOneWidget);
  });

  testWidgets('Sign in opens the agent sign-in command in Terminal', (WidgetTester tester) async {
    repository.agents = <AgentAdapter>[ScriptedAgentAdapter(id: 'claude', displayName: 'Claude Like', handler: _done, isAvailable: false, signInCommand: 'claude auth login', supportsAccounts: true)];
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('sign-in-claude')));
    await tester.pumpAndSettle();
    expect(repository.terminal, <String>['claude auth login']);
    expect(find.byKey(const Key('copy-sign-in-claude')), findsOneWidget, reason: 'the command can still be copied');
  });

  testWidgets('removing an account asks first and explains its folder is deleted', (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('remove-account-claude-personal')));
    await tester.pumpAndSettle();
    expect(find.textContaining('deletes this account\'s configuration folder'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-remove-account')));
    await tester.pumpAndSettle();

    expect(repository.removedAccounts, <String>['claude-personal']);
    expect(find.byKey(const ValueKey<String>('agent-card-claude-personal')), findsNothing);
  });
}
