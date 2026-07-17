```markdown
# STLT-Rewired Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches development conventions and workflows for the STLT-Rewired TypeScript codebase. It covers file naming, import/export styles, commit message patterns, and testing practices. Use this guide to ensure consistency and efficiency when contributing to the project.

## Coding Conventions

### File Naming
- Use **snake_case** for all file names.
  - Example:  
    ```
    user_profile.ts
    data_loader.test.ts
    ```

### Import Style
- Use **relative imports** within the codebase.
  - Example:  
    ```typescript
    import { fetchData } from './data_loader';
    ```

### Export Style
- Use **named exports** for all modules.
  - Example:  
    ```typescript
    // In data_loader.ts
    export function fetchData() { ... }
    ```

### Commit Messages
- Follow **conventional commit** format.
- Use the `fix` prefix for bug fixes.
  - Example:  
    ```
    fix: resolve issue with user authentication flow
    ```

## Workflows

### Conventional Commit
**Trigger:** When making a commit  
**Command:** `/conventional-commit`

1. Stage your changes.
2. Write a commit message using the conventional format:
    - Start with a type (e.g., `fix:`).
    - Follow with a concise description (average ~61 characters).
3. Commit your changes.

_Example:_
```
git add user_profile.ts
git commit -m "fix: correct typo in user profile display"
```

### Add New Module
**Trigger:** When creating a new feature or utility module  
**Command:** `/add-module`

1. Create a new file using snake_case naming.
2. Implement your logic.
3. Use named exports.
4. Use relative imports to include dependencies.

_Example:_
```typescript
// In data_validator.ts
export function validateInput(input: string): boolean {
  // validation logic
  return true;
}
```
```typescript
// In another file
import { validateInput } from './data_validator';
```

### Write a Test
**Trigger:** When adding or updating functionality  
**Command:** `/write-test`

1. Create a test file with the pattern `*.test.*` (e.g., `data_loader.test.ts`).
2. Implement tests for your module.
3. Use the project's preferred (unknown) test framework.

_Example:_
```typescript
// data_loader.test.ts
import { fetchData } from './data_loader';

test('fetchData returns expected data', () => {
  expect(fetchData()).toEqual(expectedData);
});
```

## Testing Patterns

- Test files follow the `*.test.*` naming convention.
- The test framework is unspecified; follow existing patterns in the repository.
- Place tests alongside or near the modules they test.
- Example test file: `user_profile.test.ts`

## Commands
| Command                | Purpose                                    |
|------------------------|--------------------------------------------|
| /conventional-commit   | Guide for writing conventional commits     |
| /add-module            | Steps for adding a new module              |
| /write-test            | Steps for writing and organizing tests     |
```
