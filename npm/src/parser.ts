import { createHash } from "crypto";
import * as yaml from "js-yaml";
import type {
  Spec,
  Capability,
  Constraint,
  AcceptanceTest,
  Dependency,
  ChangelogEntry,
  ParseResult,
  ValidationIssue,
  ValidationResult,
} from "./types.js";

/**
 * Parse a SPEC.md string into a structured Spec.
 *
 * Deterministic: same input always produces the same parse tree.
 */
export function parse(markdown: string): ParseResult {
  const sourceHash = createHash("sha256").update(markdown).digest("hex");

  // Extract frontmatter
  const fmResult = extractFrontmatter(markdown);
  if (!fmResult.ok) return fmResult;
  const { frontmatter, body } = fmResult;

  // Parse YAML
  let fmMap: Record<string, unknown>;
  try {
    const parsed = yaml.load(frontmatter);
    if (typeof parsed !== "object" || parsed === null) {
      return { ok: false, errors: ["line 1: Frontmatter must be a YAML mapping"] };
    }
    fmMap = parsed as Record<string, unknown>;
  } catch (e) {
    return { ok: false, errors: [`line 1: Invalid YAML in frontmatter: ${e}`] };
  }

  // Parse sections
  const sections = parseSections(body);

  const spec: Spec = {
    name: asString(fmMap.name),
    version: asString(fmMap.version),
    runtime: asString(fmMap.runtime) ?? "any",
    author: asString(fmMap.author),
    created: asString(fmMap.created),
    updated: asString(fmMap.updated),
    tags: asStringArray(fmMap.tags),
    dependencyNames: asStringArray(fmMap.dependencies),
    ampersandRef: asString(fmMap.ampersand_ref),
    adlRef: asString(fmMap.adl_ref),
    governance: fmMap.governance as Record<string, unknown> | undefined,
    workspaceId: asString(fmMap.workspace_id),
    visibility: parseVisibility(asString(fmMap.visibility)),
    sourceHash,
    purpose: sections.get("Purpose"),
    capabilities: parseCapabilities(sections.get("Capabilities") ?? ""),
    constraints: parseConstraints(sections.get("Constraints") ?? ""),
    acceptanceTests: parseAcceptanceTests(sections.get("Acceptance Tests") ?? ""),
    compiledTests: [],
    architecture: sections.get("Architecture"),
    dependencies: parseDependencies(sections.get("Dependencies") ?? ""),
    changelogEntries: parseChangelog(sections.get("Changelog") ?? ""),
    raw: markdown,
  };

  return { ok: true, spec };
}

/**
 * Validate a parsed Spec against all MUST and SHOULD rules (spec section 4.7).
 */
export function validate(spec: Spec): ValidationResult {
  const errors: ValidationIssue[] = [];
  const warnings: ValidationIssue[] = [];

  // MUST 1: Frontmatter present
  if (!spec.name && !spec.version && !spec.author) {
    errors.push({ severity: "error", rule: "MUST-1", message: "Frontmatter is missing or empty" });
  }

  // MUST 2: Required fields
  for (const field of ["name", "version", "author", "created", "updated"] as const) {
    if (!spec[field]) {
      errors.push({
        severity: "error",
        rule: "MUST-2",
        message: `Required frontmatter field '${field}' is missing`,
      });
    }
  }

  // MUST 3: Valid semver
  if (spec.version && !/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$/.test(spec.version)) {
    errors.push({ severity: "error", rule: "MUST-3", message: `Version '${spec.version}' is not valid semver` });
  }

  // MUST 4: Required sections
  const requiredSections: [string, unknown][] = [
    ["Purpose", spec.purpose],
    ["Capabilities", spec.capabilities],
    ["Constraints", spec.constraints],
    ["Acceptance Tests", spec.acceptanceTests],
  ];
  for (const [name, value] of requiredSections) {
    if (!value || (Array.isArray(value) && value.length === 0) || value === "") {
      errors.push({ severity: "error", rule: "MUST-4", message: `Required section '${name}' is missing` });
    }
  }

  // MUST 5: Minimum content
  if (spec.capabilities.length === 0) {
    errors.push({ severity: "error", rule: "MUST-5", message: "At least one capability is required" });
  }
  if (spec.constraints.length === 0) {
    errors.push({ severity: "error", rule: "MUST-5", message: "At least one constraint is required" });
  }
  if (spec.acceptanceTests.length === 0) {
    errors.push({ severity: "error", rule: "MUST-5", message: "At least one acceptance test is required" });
  }

  // MUST 6: Capability format (check raw for unparsed lines)
  const capSection = extractSectionText(spec.raw, "Capabilities");
  if (capSection) {
    const rawLines = capSection.split("\n").map((l) => l.trim()).filter((l) => l.startsWith("- "));
    if (rawLines.length > spec.capabilities.length) {
      const unparsed = rawLines.length - spec.capabilities.length;
      errors.push({
        severity: "error",
        rule: "MUST-6",
        message: `${unparsed} capability line(s) do not match 'capability:scope (description)' format`,
      });
    }
  }

  // MUST 7: Acceptance test format
  const testSection = extractSectionText(spec.raw, "Acceptance Tests");
  if (testSection) {
    const rawLines = testSection.split("\n").map((l) => l.trim()).filter((l) => l.startsWith("- "));
    if (rawLines.length > spec.acceptanceTests.length) {
      const unparsed = rawLines.length - spec.acceptanceTests.length;
      errors.push({
        severity: "error",
        rule: "MUST-7",
        message: `${unparsed} acceptance test line(s) do not match 'Given X → Y' or 'When X, then Y' format`,
      });
    }
  }

  // SHOULD 1: Empty sections
  if (spec.purpose !== undefined && spec.purpose.trim() === "") {
    warnings.push({ severity: "warning", rule: "SHOULD-1", message: "Section 'Purpose' is present but empty" });
  }

  // SHOULD 2: Tests referencing capabilities
  const capNames = spec.capabilities.map((c) => c.capability.toLowerCase());
  const capScopes = spec.capabilities.map((c) => `${c.capability}:${c.scope}`.toLowerCase());
  const allRefs = [...capNames, ...capScopes];
  spec.acceptanceTests.forEach((test, idx) => {
    const testText = `${test.given} ${test.expected}`.toLowerCase();
    if (!allRefs.some((ref) => testText.includes(ref))) {
      warnings.push({
        severity: "warning",
        rule: "SHOULD-2",
        message: `Acceptance test ${idx + 1} does not reference any declared capability`,
      });
    }
  });

  // SHOULD 3: Ambiguous constraints
  const ambiguousPattern = /\b(try to|usually|sometimes|might|perhaps|if possible)\b/i;
  spec.constraints.forEach((c, idx) => {
    if (ambiguousPattern.test(c.text)) {
      warnings.push({
        severity: "warning",
        rule: "SHOULD-3",
        message: `Constraint ${idx + 1} uses ambiguous language (try to, usually, sometimes)`,
      });
    }
  });

  // SHOULD 4: Changelog for post-v1
  if (spec.version && spec.version > "1.0.0" && spec.changelogEntries.length === 0) {
    warnings.push({
      severity: "warning",
      rule: "SHOULD-4",
      message: "Versions > 1.0.0 should include a changelog",
    });
  }

  // SHOULD 5: Unapproved compiled tests
  const unapproved = spec.compiledTests.filter((t) => !t.approved);
  if (unapproved.length > 0) {
    warnings.push({
      severity: "warning",
      rule: "SHOULD-5",
      message: `${unapproved.length} compiled test(s) are not approved — will not be used in dark factory pipeline`,
    });
  }

  return { valid: errors.length === 0, errors, warnings };
}

// --- Frontmatter extraction ---

function extractFrontmatter(
  markdown: string
): { ok: true; frontmatter: string; body: string } | { ok: false; errors: string[] } {
  const parts = markdown.split(/^---\s*$/m);
  if (parts.length >= 3 && parts[0].trim() === "") {
    return { ok: true, frontmatter: parts[1].trim(), body: parts.slice(2).join("---").trim() };
  }
  return {
    ok: false,
    errors: ["line 1: Missing or invalid YAML frontmatter (must be enclosed in --- delimiters)"],
  };
}

// --- Section parsing ---

function parseSections(body: string): Map<string, string> {
  const sections = new Map<string, string>();
  const parts = body.split(/^## /m);

  for (const part of parts) {
    if (part.trim() === "") continue;
    const newlineIdx = part.indexOf("\n");
    if (newlineIdx === -1) {
      sections.set(part.trim(), "");
    } else {
      const heading = part.substring(0, newlineIdx).trim();
      const content = part.substring(newlineIdx + 1).trim();
      sections.set(heading, content);
    }
  }

  return sections;
}

// --- Capability parsing ---

const CAPABILITY_RE = /^([a-z][a-z0-9_]*):([a-z][a-z0-9_]*)\s*\((.+)\)$/;
const CAPABILITY_NO_DESC_RE = /^([a-z][a-z0-9_]*):([a-z][a-z0-9_]*)$/;

function parseCapabilities(text: string): Capability[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("- "))
    .map((l) => l.slice(2))
    .map((line): Capability | null => {
      let match = CAPABILITY_RE.exec(line);
      if (match) {
        return { capability: match[1], scope: match[2], description: match[3].trim() };
      }
      match = CAPABILITY_NO_DESC_RE.exec(line.trim());
      if (match) {
        return { capability: match[1], scope: match[2] };
      }
      return null;
    })
    .filter((c): c is Capability => c !== null);
}

// --- Constraint parsing ---

function parseConstraints(text: string): Constraint[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("- "))
    .map((l) => l.slice(2))
    .map((line): Constraint => {
      let type: Constraint["type"] = "unclassified";
      if (/^(Never|Always|Must)/i.test(line)) type = "hard";
      else if (/^(Prefer|Try to|Usually|Sometimes)/i.test(line)) type = "soft";
      else if (line.startsWith("Hard: ")) type = "hard";
      else if (line.startsWith("Soft: ")) type = "soft";
      return { text: line, type };
    });
}

// --- Acceptance test parsing ---

function parseAcceptanceTests(text: string): AcceptanceTest[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("- "))
    .map((l) => l.slice(2))
    .map((line): AcceptanceTest | null => {
      if (line.startsWith("Given ")) {
        const parts = line.slice(6).split(" → ", 2);
        if (parts.length === 2) {
          return { given: parts[0].trim(), expected: parts[1].trim(), format: "given_then" };
        }
      } else if (line.startsWith("When ")) {
        const parts = line.slice(5).split(", then ", 2);
        if (parts.length === 2) {
          return { given: parts[0].trim(), expected: parts[1].trim(), format: "when_then" };
        }
      }
      return null;
    })
    .filter((t): t is AcceptanceTest => t !== null);
}

// --- Dependency parsing ---

const DEPENDENCY_RE = /^(.+?)\s*\((.+)\)$/;

function parseDependencies(text: string): Dependency[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("- "))
    .map((l) => l.slice(2))
    .map((line): Dependency => {
      const match = DEPENDENCY_RE.exec(line);
      if (match) {
        const [type, location] = parseDependencyDetail(match[2]);
        return { name: match[1].trim(), type, location };
      }
      return { name: line.trim() };
    });
}

function parseDependencyDetail(detail: string): [string?, string?] {
  const parts = detail.split(",", 2).map((p) => p.trim());
  if (parts.length === 2) {
    const location = parts[1].startsWith("remote: ") ? parts[1].slice(8) : parts[1];
    return [parts[0], location];
  }
  return [parts[0], undefined];
}

// --- Changelog parsing ---

const CHANGELOG_RE = /^(.+?)\s*\((.+?)\):\s*(.+)$/;

function parseChangelog(text: string): ChangelogEntry[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("- "))
    .map((l) => l.slice(2))
    .map((line): ChangelogEntry | null => {
      const match = CHANGELOG_RE.exec(line);
      if (match) {
        return { version: match[1].trim(), date: match[2].trim(), description: match[3].trim() };
      }
      return null;
    })
    .filter((e): e is ChangelogEntry => e !== null);
}

// --- Helpers ---

function parseVisibility(v?: string): "private" | "workspace" | "public" {
  if (v === "private") return "private";
  if (v === "public") return "public";
  return "workspace";
}

function asString(val: unknown): string | undefined {
  if (val === null || val === undefined) return undefined;
  if (val instanceof Date) return val.toISOString().split("T")[0];
  return String(val);
}

function asStringArray(val: unknown): string[] {
  if (Array.isArray(val)) return val.map(String);
  return [];
}

function extractSectionText(raw: string, sectionName: string): string | undefined {
  const escaped = sectionName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`^## ${escaped}\\s*\\n([\\s\\S]*?)(?=^## |$)`, "m");
  const match = re.exec(raw);
  return match?.[1]?.trim();
}
