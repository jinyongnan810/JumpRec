# AGENTS.md

## Purpose
This repository contains a SwiftUI application.  
When making changes, prioritize readability, maintainability, and safety over cleverness or unnecessary abstraction.

## General coding rules
- Write clear, simple, and production-friendly Swift code.
- Prefer straightforward solutions over overly abstract designs.
- Keep files and types focused on a single responsibility.
- Avoid introducing new dependencies unless clearly justified.
- Preserve existing architecture unless there is a strong reason to improve it.
- Do not make broad refactors unless they are required for the task.
- Also implement localization if ui changes

## Readability and comments
- Keep comments concise and plain; prefer one line when possible.
- Describe the code as it is: current behavior, constraints, and intent.
- Do not include implementation stories, commit history, or descriptions of earlier designs.
- Explain non-obvious logic, state transitions, edge cases, and platform quirks only when useful.
- Do not restate what the code already makes clear.
- Use `///` for useful type, property, and function documentation.
- Use longer comments only when a short comment would omit an essential detail.

## Naming
- Use descriptive names.
- Prefer full words over unclear abbreviations.
- Name views with nouns that describe what they render.
- Name actions and methods with verbs that describe what they do.
- Name booleans so they read clearly at call sites, such as `isLoading`, `hasPermission`, or `canSubmit`.

## Error handling
- Handle errors explicitly where possible.
- Avoid silent failures unless there is a good UX reason.
- When swallowing an error intentionally, leave a comment explaining why.
- Surface user-facing errors in a clear and non-technical way.
- Log useful debugging context when appropriate.

## State management
- Keep state as local as possible.
- Avoid duplicating derived state.
- Prefer a single source of truth for important UI state.
- Document tricky synchronization or lifecycle behavior.

## File organization
- Keep related code grouped logically.
- Use `// MARK:` sections to improve navigation.
- Suggested section order for Swift types when applicable:
  1. public API
  2. stored properties
  3. initialization
  4. body
  5. helpers
  6. private subviews
- Do not let files grow without reason. Split them when doing so improves readability.

## Previews
- Add or update SwiftUI previews when it meaningfully helps understand the view.
- Keep previews simple and useful.
- Include multiple states when helpful, such as loading, error, empty, and populated.

## Building and Testing
- Do NOT run unit tests unless explicitly asked by the user.
- Always use Xcode MCP tools (`xcode` server `BuildProject` tool) for building the project instead of running shell `xcodebuild` commands with custom output directories (which create unwanted `./build` folders in the repository root).
- Prefer code that is easy to test.
- Add or update tests for non-trivial logic when appropriate.
- For bug fixes, consider adding a test that covers the regression.
- Do not add fragile tests with little long-term value.
- Run `make lint` after editing.

## Editing existing code
- Match the style of the existing codebase unless it is clearly harmful.
- Preserve behavior unless the task explicitly requires changing it.
- When changing a non-obvious implementation, update comments to reflect the new behavior.
- Do not remove useful comments unless replacing them with better ones.

## Output expectations
When making changes in this repository:
- Keep useful comments short, plain, and focused on the current code.
- Explain non-obvious choices without implementation history.
- Avoid unnecessary complexity.
- Preserve maintainability for future readers.
