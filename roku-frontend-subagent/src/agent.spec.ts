import { describe, expect, it } from "vitest";
import { RokuFrontendAgent } from "./agent";

describe("RokuFrontendAgent", () => {
  it("should instantiate with required config", () => {
    const agent = new RokuFrontendAgent({
      apiKey: "test-key",
    });
    expect(agent).toBeDefined();
  });

  it("should accept optional config overrides", () => {
    const agent = new RokuFrontendAgent({
      apiKey: "test-key",
      model: "claude-opus-4-20250514",
      maxTokens: 8192,
      workingDirectory: "/tmp/roku-project",
    });
    expect(agent).toBeDefined();
  });
});
