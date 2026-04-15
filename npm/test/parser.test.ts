import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { join } from "path";
import { parse, validate } from "../src/parser.js";

const FIXTURES = join(__dirname, "../../test/fixtures");
const validSpec = readFileSync(join(FIXTURES, "valid_spec.md"), "utf-8");
const invalidSpec = readFileSync(join(FIXTURES, "invalid_spec.md"), "utf-8");

describe("parse", () => {
  describe("with valid customer-support spec", () => {
    it("returns ok: true", () => {
      const result = parse(validSpec);
      expect(result.ok).toBe(true);
    });

    it("parses frontmatter fields", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      const spec = result.spec;

      expect(spec.name).toBe("customer-support-v2");
      expect(spec.version).toBe("2.1.0");
      expect(spec.runtime).toBe("opensentience");
      expect(spec.author).toBe("ops-team");
      expect(spec.created).toBe("2026-02-15");
      expect(spec.updated).toBe("2026-02-22");
      expect(spec.tags).toEqual(["support", "customer-facing", "e-commerce"]);
      expect(spec.dependencyNames).toEqual(["graphonomous", "orders-api", "notifications-service"]);
    });

    it("computes source hash", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.sourceHash).toHaveLength(64);
    });

    it("parses purpose section", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.purpose).toContain("Handle customer inquiries");
      expect(result.spec.purpose).toContain("Graphonomous");
    });

    it("parses 5 capabilities", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.capabilities).toHaveLength(5);

      const first = result.spec.capabilities[0];
      expect(first.capability).toBe("orders");
      expect(first.scope).toBe("read");
      expect(first.description).toContain("order status");
    });

    it("parses 6 constraints", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.constraints).toHaveLength(6);

      const first = result.spec.constraints[0];
      expect(first.text).toContain("Never disclose");
      expect(first.type).toBe("hard");
    });

    it("classifies constraint types", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      const types = result.spec.constraints.map((c) => c.type);
      expect(types.filter((t) => t === "hard").length).toBeGreaterThanOrEqual(4);
    });

    it("parses 8 acceptance tests", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.acceptanceTests).toHaveLength(8);

      const first = result.spec.acceptanceTests[0];
      expect(first.format).toBe("given_then");
      expect(first.given).toContain("valid order #123");
      expect(first.expected).toContain("current status");
    });

    it("parses architecture section", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.architecture).toContain("Graphonomous");
      expect(result.spec.architecture).toContain("Refund workflow");
    });

    it("parses 3 dependencies with details", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.dependencies).toHaveLength(3);

      const first = result.spec.dependencies[0];
      expect(first.name).toBe("graphonomous");
      expect(first.type).toBe("MCP server");
      expect(first.location).toBe("local");
    });

    it("parses 3 changelog entries", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.changelogEntries).toHaveLength(3);

      const first = result.spec.changelogEntries[0];
      expect(first.version).toBe("2.1.0");
      expect(first.date).toBe("2026-02-22");
      expect(first.description).toContain("Graphonomous");
    });

    it("is deterministic", () => {
      const r1 = parse(validSpec);
      const r2 = parse(validSpec);
      if (!r1.ok || !r2.ok) throw new Error("expected ok");
      expect(r1.spec.sourceHash).toBe(r2.spec.sourceHash);
      expect(r1.spec.capabilities.length).toBe(r2.spec.capabilities.length);
      expect(r1.spec.acceptanceTests.length).toBe(r2.spec.acceptanceTests.length);
    });
  });

  describe("with invalid spec", () => {
    it("parses but has empty required sections", () => {
      const result = parse(invalidSpec);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.name).toBe("broken-agent");
      expect(result.spec.version).toBeUndefined();
      expect(result.spec.capabilities).toHaveLength(0);
      expect(result.spec.acceptanceTests).toHaveLength(0);
    });
  });

  describe("with missing frontmatter", () => {
    it("returns error", () => {
      const result = parse("# No Frontmatter\n\nJust text.");
      expect(result.ok).toBe(false);
      if (result.ok) throw new Error("expected error");
      expect(result.errors[0]).toContain("frontmatter");
    });
  });

  describe("with When/then format", () => {
    it("parses When X, then Y tests", () => {
      const md = `---
name: test-agent
version: 1.0.0
author: test
created: 2026-01-01
updated: 2026-01-01
---

## Purpose

A test agent.

## Capabilities

- api:read (read data)

## Constraints

- Never crash

## Acceptance Tests

- When user asks for help, then provide assistance
- Given error occurs → handle gracefully
`;

      const result = parse(md);
      if (!result.ok) throw new Error("expected ok");
      expect(result.spec.acceptanceTests).toHaveLength(2);

      const [whenTest, givenTest] = result.spec.acceptanceTests;
      expect(whenTest.format).toBe("when_then");
      expect(whenTest.given).toBe("user asks for help");
      expect(whenTest.expected).toBe("provide assistance");
      expect(givenTest.format).toBe("given_then");
    });
  });
});

describe("validate", () => {
  describe("with valid spec", () => {
    it("passes validation", () => {
      const result = parse(validSpec);
      if (!result.ok) throw new Error("expected ok");
      const validation = validate(result.spec);
      expect(validation.valid).toBe(true);
      expect(validation.errors).toHaveLength(0);
    });
  });

  describe("with invalid spec", () => {
    it("fails validation", () => {
      const result = parse(invalidSpec);
      if (!result.ok) throw new Error("expected ok");
      const validation = validate(result.spec);
      expect(validation.valid).toBe(false);
      expect(validation.errors.length).toBeGreaterThan(0);
    });

    it("reports missing required fields", () => {
      const result = parse(invalidSpec);
      if (!result.ok) throw new Error("expected ok");
      const validation = validate(result.spec);
      const must2 = validation.errors.filter((e) => e.rule === "MUST-2");
      expect(must2.some((e) => e.message.includes("version"))).toBe(true);
      expect(must2.some((e) => e.message.includes("author"))).toBe(true);
    });

    it("reports missing capabilities and tests", () => {
      const result = parse(invalidSpec);
      if (!result.ok) throw new Error("expected ok");
      const validation = validate(result.spec);
      const must5 = validation.errors.filter((e) => e.rule === "MUST-5");
      expect(must5.some((e) => e.message.includes("capability"))).toBe(true);
      expect(must5.some((e) => e.message.includes("acceptance test"))).toBe(true);
    });

    it("reports bad capability format", () => {
      const result = parse(invalidSpec);
      if (!result.ok) throw new Error("expected ok");
      const validation = validate(result.spec);
      const must6 = validation.errors.filter((e) => e.rule === "MUST-6");
      expect(must6.length).toBeGreaterThan(0);
    });

    it("reports bad test format", () => {
      const result = parse(invalidSpec);
      if (!result.ok) throw new Error("expected ok");
      const validation = validate(result.spec);
      const must7 = validation.errors.filter((e) => e.rule === "MUST-7");
      expect(must7.length).toBeGreaterThan(0);
    });
  });

  describe("SHOULD-3 ambiguous constraints", () => {
    it("warns on ambiguous language", () => {
      const md = `---
name: test
version: 1.0.0
author: test
created: 2026-01-01
updated: 2026-01-01
---

## Purpose

Test.

## Capabilities

- a:b (test)

## Constraints

- Try to respond quickly
- Never crash

## Acceptance Tests

- Given x → y
`;
      const result = parse(md);
      if (!result.ok) throw new Error("expected ok");
      const validation = validate(result.spec);
      const should3 = validation.warnings.filter((w) => w.rule === "SHOULD-3");
      expect(should3).toHaveLength(1);
    });
  });
});
