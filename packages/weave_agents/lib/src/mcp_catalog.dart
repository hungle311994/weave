import 'mcp_server.dart';

/// Where a [McpCatalogEntry] is listed.
enum McpCatalogCategory {
  popular('Popular'),
  docsAndData('Docs & data'),
  browser('Browser');

  const McpCatalogCategory(this.label);

  final String label;
}

/// A well-known MCP server the user can add with one click. Tokens are
/// `${NAME}` references read from the environment when a workflow starts;
/// nothing here holds a credential.
final class McpCatalogEntry {
  const McpCatalogEntry({required this.category, required this.server});

  final McpCatalogCategory category;

  /// What is written to `mcp.json` when the entry is added.
  final McpServerDefinition server;
}

/// Servers whose publishers document a token-in-header, token-in-environment
/// or no-sign-in setup, so they run without an interactive OAuth step.
List<McpCatalogEntry> get mcpCatalog => <McpCatalogEntry>[
  McpCatalogEntry(
    category: McpCatalogCategory.popular,
    server: McpServerDefinition(
      id: 'github',
      displayName: 'GitHub',
      description: 'Issues, pull requests, code search and Actions',
      brand: 'github',
      transport: McpHttpTransport(url: 'https://api.githubcopilot.com/mcp/', headers: const <String, String>{'Authorization': r'Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}'}),
      linkPatterns: const <String>[r'https?://github\.com/[^/\s]+/[^/\s]+'],
      setupHint: r'Create a GitHub personal access token and set $GITHUB_PERSONAL_ACCESS_TOKEN.',
    ),
  ),
  McpCatalogEntry(
    category: McpCatalogCategory.popular,
    server: McpServerDefinition(
      id: 'linear',
      displayName: 'Linear',
      description: 'Issues, projects and cycles',
      brand: 'linear',
      transport: McpHttpTransport(url: 'https://mcp.linear.app/mcp', headers: const <String, String>{'Authorization': r'Bearer ${LINEAR_API_KEY}'}),
      linkPatterns: const <String>[r'https?://linear\.app/\S+'],
      setupHint: r'Create a personal API key in Linear (Settings › Security & access) and set $LINEAR_API_KEY.',
    ),
  ),
  McpCatalogEntry(
    category: McpCatalogCategory.popular,
    server: McpServerDefinition(
      id: 'notion',
      displayName: 'Notion',
      description: 'Pages and databases shared with your integration',
      transport: McpStdioTransport(command: 'npx', arguments: const <String>['-y', '@notionhq/notion-mcp-server'], environment: const <String, String>{'NOTION_TOKEN': r'${NOTION_TOKEN}'}),
      linkPatterns: const <String>[r'https?://(www\.)?notion\.so/\S+'],
      setupHint: r'Create a Notion integration, share pages with it, and set $NOTION_TOKEN to its secret. Needs Node.js (npx).',
    ),
  ),
  McpCatalogEntry(
    category: McpCatalogCategory.popular,
    server: McpServerDefinition(
      id: 'sentry',
      displayName: 'Sentry',
      description: 'Errors, issues and stack traces',
      brand: 'sentry',
      transport: McpStdioTransport(command: 'npx', arguments: const <String>['-y', '@sentry/mcp-server@latest'], environment: const <String, String>{'SENTRY_ACCESS_TOKEN': r'${SENTRY_ACCESS_TOKEN}'}),
      linkPatterns: const <String>[r'https?://[^/\s]*sentry\.io/\S+'],
      setupHint: r'Create a Sentry user auth token and set $SENTRY_ACCESS_TOKEN. Needs Node.js (npx).',
    ),
  ),
  McpCatalogEntry(
    category: McpCatalogCategory.docsAndData,
    server: McpServerDefinition(
      id: 'context7',
      displayName: 'Context7',
      description: 'Current documentation and examples for libraries',
      transport: McpHttpTransport(url: 'https://mcp.context7.com/mcp', headers: const <String, String>{'CONTEXT7_API_KEY': r'${CONTEXT7_API_KEY}'}),
      setupHint: r'Create a Context7 API key and set $CONTEXT7_API_KEY.',
    ),
  ),
  McpCatalogEntry(
    category: McpCatalogCategory.docsAndData,
    server: McpServerDefinition(
      id: 'supabase',
      displayName: 'Supabase',
      description: 'Read-only access to your Supabase projects and databases',
      transport: McpStdioTransport(command: 'npx', arguments: const <String>['-y', '@supabase/mcp-server-supabase@latest', '--read-only'], environment: const <String, String>{'SUPABASE_ACCESS_TOKEN': r'${SUPABASE_ACCESS_TOKEN}'}),
      setupHint: r'Create a Supabase personal access token and set $SUPABASE_ACCESS_TOKEN. Needs Node.js (npx).',
    ),
  ),
  McpCatalogEntry(
    category: McpCatalogCategory.docsAndData,
    server: McpServerDefinition(
      id: 'stripe',
      displayName: 'Stripe',
      description: 'Customers, payments and Stripe docs',
      transport: McpHttpTransport(url: 'https://mcp.stripe.com', headers: const <String, String>{'Authorization': r'Bearer ${STRIPE_SECRET_KEY}'}),
      setupHint: r'Set $STRIPE_SECRET_KEY to a restricted key with only the access agents need.',
    ),
  ),
  McpCatalogEntry(
    category: McpCatalogCategory.browser,
    server: McpServerDefinition(
      id: 'playwright',
      displayName: 'Playwright',
      description: 'Open pages, click and fill forms in a browser',
      transport: McpStdioTransport(command: 'npx', arguments: const <String>['-y', '@playwright/mcp@latest']),
      setupHint: 'No sign-in needed. Needs Node.js (npx).',
    ),
  ),
  McpCatalogEntry(
    category: McpCatalogCategory.browser,
    server: McpServerDefinition(
      id: 'chrome-devtools',
      displayName: 'Chrome DevTools',
      description: 'Inspect, debug and profile pages in Chrome',
      transport: McpStdioTransport(command: 'npx', arguments: const <String>['-y', 'chrome-devtools-mcp@latest']),
      setupHint: 'No sign-in needed. Needs Node.js (npx) and Google Chrome.',
    ),
  ),
];
