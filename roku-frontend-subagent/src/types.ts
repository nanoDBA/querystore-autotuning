export interface RokuFrontendAgentConfig {
  /** Anthropic API key for Claude interactions */
  apiKey: string;
  /** Model to use for agent tasks */
  model?: string;
  /** Maximum tokens per response */
  maxTokens?: number;
  /** Working directory for file operations */
  workingDirectory?: string;
}

export interface RokuChannel {
  /** Channel identifier */
  id: string;
  /** Channel display name */
  name: string;
  /** BrightScript entry point */
  entryPoint: string;
  /** Scene graph XML components */
  components: RokuComponent[];
}

export interface RokuComponent {
  /** Component name */
  name: string;
  /** Component type (Task, Scene, Group, etc.) */
  type: "Task" | "Scene" | "Group" | "Label" | "Poster" | "Custom";
  /** Path to the XML definition */
  xmlPath: string;
  /** Path to the BrightScript source */
  brsPath?: string;
  /** Child component references */
  children?: string[];
}

export interface AgentTask {
  /** Unique task identifier */
  id: string;
  /** Task description */
  description: string;
  /** Task type */
  type:
    | "scaffold"
    | "component"
    | "screen"
    | "navigation"
    | "style"
    | "review";
  /** Additional context for the task */
  context?: Record<string, unknown>;
}

export interface AgentResult {
  /** Whether the task completed successfully */
  success: boolean;
  /** Task that was executed */
  task: AgentTask;
  /** Generated or modified files */
  files: Array<{ path: string; action: "created" | "modified" | "deleted" }>;
  /** Summary of changes */
  summary: string;
}
