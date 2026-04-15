/** Parsed capability from the Capabilities section. */
export interface Capability {
  capability: string;
  scope: string;
  description?: string;
  mapsTo?: string;
}

/** Parsed constraint from the Constraints section. */
export interface Constraint {
  text: string;
  type: "hard" | "soft" | "unclassified";
  mapsToGovernance?: string;
}

/** Parsed acceptance test from the Acceptance Tests section. */
export interface AcceptanceTest {
  given: string;
  expected: string;
  format: "given_then" | "when_then";
}

/** Compiled test (machine-executable form of an AcceptanceTest). */
export interface CompiledTest {
  testIndex: number;
  setup?: Record<string, unknown>;
  input?: string;
  assertions: Assertion[];
  approved: boolean;
  approvedBy?: string;
  compiledAt?: string;
  compilerModel?: string;
}

/** Agentelic DSL assertion. */
export interface Assertion {
  type:
    | "contains"
    | "tool_called"
    | "tool_not_called"
    | "escalated"
    | "constraint_respected";
  value?: unknown;
  tool?: string;
  args?: Record<string, unknown>;
  constraintIndex?: number;
}

/** Parsed dependency from the Dependencies section. */
export interface Dependency {
  name: string;
  type?: string;
  location?: string;
}

/** Parsed changelog entry from the Changelog section. */
export interface ChangelogEntry {
  version: string;
  date?: string;
  description: string;
}

/** YAML frontmatter fields. */
export interface Frontmatter {
  name?: string;
  version?: string;
  runtime?: string;
  author?: string;
  created?: string;
  updated?: string;
  tags?: string[];
  dependencies?: string[];
  ampersandRef?: string;
  adlRef?: string;
  governance?: Record<string, unknown>;
  workspaceId?: string;
  visibility?: "private" | "workspace" | "public";
  sourceHash?: string;
}

/** The full parsed SPEC.md representation. */
export interface Spec {
  /** Frontmatter fields */
  name?: string;
  version?: string;
  runtime: string;
  author?: string;
  created?: string;
  updated?: string;
  tags: string[];
  dependencyNames: string[];
  ampersandRef?: string;
  adlRef?: string;
  governance?: Record<string, unknown>;
  workspaceId?: string;
  visibility: "private" | "workspace" | "public";

  /** Source tracking */
  sourceHash: string;

  /** Parsed sections */
  purpose?: string;
  capabilities: Capability[];
  constraints: Constraint[];
  acceptanceTests: AcceptanceTest[];
  compiledTests: CompiledTest[];
  architecture?: string;
  dependencies: Dependency[];
  changelogEntries: ChangelogEntry[];

  /** Raw content */
  raw: string;
}

/** Validation issue. */
export interface ValidationIssue {
  severity: "error" | "warning";
  rule: string;
  message: string;
}

/** Validation result. */
export interface ValidationResult {
  valid: boolean;
  errors: ValidationIssue[];
  warnings: ValidationIssue[];
}

/** Parse result — either success or error. */
export type ParseResult =
  | { ok: true; spec: Spec }
  | { ok: false; errors: string[] };
