import Anthropic from "@anthropic-ai/sdk";
import type {
  AgentResult,
  AgentTask,
  RokuFrontendAgentConfig,
} from "./types";

const SYSTEM_PROMPT = `You are a Roku frontend development subagent specialized in BrightScript and SceneGraph XML.

You help with:
- Scaffolding Roku channel projects (manifest, components, source)
- Creating SceneGraph XML components (Scenes, Groups, Tasks, custom nodes)
- Writing BrightScript (.brs) business logic and event handlers
- Building navigation flows between screens
- Styling components with Roku's layout system (Group, LayoutGroup, MarkupGrid)
- Reviewing Roku frontend code for best practices and performance

Follow Roku development conventions:
- Use SceneGraph XML for UI component definitions
- Use BrightScript for component logic in <script> blocks or .brs files
- Respect the Roku single-threaded render model
- Prefer observeField/observeFieldScoped for reactive data binding
- Use Task nodes for async operations (network, file I/O)
- Follow the channel certification checklist guidelines`;

export class RokuFrontendAgent {
  private client: Anthropic;
  private model: string;
  private maxTokens: number;
  private workingDirectory: string;

  constructor(config: RokuFrontendAgentConfig) {
    this.client = new Anthropic({ apiKey: config.apiKey });
    this.model = config.model ?? "claude-sonnet-4-20250514";
    this.maxTokens = config.maxTokens ?? 4096;
    this.workingDirectory = config.workingDirectory ?? process.cwd();
  }

  async execute(task: AgentTask): Promise<AgentResult> {
    const userPrompt = this.buildPrompt(task);

    const response = await this.client.messages.create({
      model: this.model,
      max_tokens: this.maxTokens,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userPrompt }],
    });

    const content = response.content
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join("\n");

    const files = this.parseFileOperations(content);

    return {
      success: true,
      task,
      files,
      summary: this.extractSummary(content),
    };
  }

  private buildPrompt(task: AgentTask): string {
    const parts = [`Task: ${task.description}`, `Type: ${task.type}`];

    if (task.context) {
      parts.push(`Context: ${JSON.stringify(task.context)}`);
    }

    parts.push(
      `Working directory: ${this.workingDirectory}`,
      "",
      "Respond with the file contents to create or modify. Use the format:",
      "--- FILE: <path> ---",
      "<content>",
      "--- END FILE ---",
      "",
      "End with a brief summary of what was done."
    );

    return parts.join("\n");
  }

  private parseFileOperations(
    content: string
  ): AgentResult["files"] {
    const files: AgentResult["files"] = [];
    const filePattern = /--- FILE: (.+?) ---/g;
    let match: RegExpExecArray | null;

    while ((match = filePattern.exec(content)) !== null) {
      files.push({ path: match[1].trim(), action: "created" });
    }

    return files;
  }

  private extractSummary(content: string): string {
    const lastFileEnd = content.lastIndexOf("--- END FILE ---");
    if (lastFileEnd === -1) return content.trim();

    const afterFiles = content.slice(lastFileEnd + "--- END FILE ---".length);
    return afterFiles.trim() || "Task completed.";
  }
}
