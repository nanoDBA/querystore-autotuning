# @nanodba/roku-frontend-subagent

A Claude Code subagent for Roku frontend development and orchestration, built following the [VoltAgent](https://github.com/VoltAgent/voltagent) subagent pattern.

## Features

- Scaffold Roku channel projects (manifest, components, source structure)
- Create SceneGraph XML components (Scene, Group, Task, custom nodes)
- Write BrightScript business logic and event handlers
- Build navigation flows between screens
- Style components using Roku's layout system
- Review Roku frontend code for best practices and performance

## Installation

```bash
npm install @nanodba/roku-frontend-subagent
```

## Usage

```typescript
import { RokuFrontendAgent } from "@nanodba/roku-frontend-subagent";

const agent = new RokuFrontendAgent({
  apiKey: process.env.ANTHROPIC_API_KEY!,
});

const result = await agent.execute({
  id: "task-1",
  description: "Create a video player screen with playback controls",
  type: "screen",
  context: {
    channelName: "MyStreamingApp",
  },
});

console.log(result.summary);
console.log(result.files);
```

## Task Types

| Type | Description |
|------|-------------|
| `scaffold` | Generate a new Roku channel project structure |
| `component` | Create a SceneGraph XML component |
| `screen` | Build a complete screen with navigation |
| `navigation` | Set up navigation flows between screens |
| `style` | Apply styling and layout to components |
| `review` | Review existing Roku frontend code |

## Development

```bash
pnpm install
pnpm dev        # Watch mode
pnpm build      # Production build
pnpm test       # Run tests
pnpm lint       # Check code style
```

## License

MIT
