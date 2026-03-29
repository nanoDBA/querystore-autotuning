# Roku Frontend Subagent

A Claude Code subagent specialized in Roku frontend development using BrightScript and SceneGraph XML.

## What is this?

This subagent handles Roku channel frontend tasks: scaffolding projects, creating SceneGraph components, writing BrightScript logic, building navigation flows, and reviewing code for Roku best practices.

## Overview

- View [`src/agent.ts`](./src/agent.ts) for the main agent implementation
- View [`src/types.ts`](./src/types.ts) for type definitions
- View [`src/agent.spec.ts`](./src/agent.spec.ts) for tests

## Validating Changes

```bash
pnpm test        # Run all tests
pnpm build       # Build the package
pnpm lint        # Run linting checks
pnpm lint:fix    # Auto-fix linting issues
```

## Important Notes for AI Agents

1. **BrightScript conventions** - Use SceneGraph XML for UI, BrightScript for logic
2. **Roku threading model** - All UI runs on the render thread; use Task nodes for async work
3. **Reactive patterns** - Use `observeField`/`observeFieldScoped` for data binding
4. **Type safety** - This is a TypeScript-first codebase; maintain strict types
5. **Test your changes** - Ensure all tests pass before committing
