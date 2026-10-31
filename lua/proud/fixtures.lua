local M = {}

M.pull_requests = {
  {
    number = 482,
    title = "Add retry backoff to robot task runner",
    author = { login = "sara-k" },
    age = "2h",
    additions = 134,
    deletions = 17,
    threads = 3,
    review_decision = "CHANGES_REQUESTED",
    is_draft = false,
    labels = { "runner", "reliability" },
    body = "Exponential retry backoff with jitter and bounded runner limits.",
    reviewers = {
      { login = "dev-lee", state = "changes_requested", age = "1h" },
      { login = "morteza", state = "pending", age = "" },
    },
    head_ref = "feat/task-retry-backoff",
    base_ref = "main",
  },
  {
    number = 479,
    title = "Fix Capture list pagination on infinite scroll",
    author = { login = "dev-lee" },
    age = "5h",
    additions = 58,
    deletions = 22,
    threads = 1,
    review_decision = "REVIEW_REQUIRED",
    is_draft = false,
    labels = { "capture" },
    head_ref = "fix/capture-pagination",
    base_ref = "main",
  },
  {
    number = 477,
    title = "Respect workspace timezone in monitor schedules",
    author = { login = "amir-r" },
    age = "1d",
    additions = 201,
    deletions = 40,
    threads = 0,
    review_decision = "REVIEW_REQUIRED",
    is_draft = false,
    labels = { "monitor" },
    head_ref = "feat/monitor-timezone",
    base_ref = "main",
  },
}

M.overview = {
  number = 482,
  title = "Add retry backoff to robot task runner",
  author = "sara-k",
  state = "Open",
  head_ref = "feat/task-retry-backoff",
  base_ref = "main",
  labels = { "runner", "reliability" },
  milestone = "Q4 runner hardening",
  reviewers = {
    { login = "dev-lee", state = "changes_requested", age = "1h" },
    { login = "morteza", state = "pending", age = "" },
  },
  reviews = {
    {
      id = 100,
      author = "dev-lee",
      state = "changes_requested",
      age = "1h",
      body = "Backoff math is off by one in retry.ts.",
    },
  },
  comments = {
    {
      id = 201,
      reply_to_id = "100",
      author = "sara-k",
      age = "40m",
      body = "Good catch. Pushing a fix in the next commit.",
    },
  },
  body = {
    "## Summary",
    "Tasks that hit a transient error used to retry with a flat delay.",
    "This adds exponential backoff with jitter and reads limits from runner config.",
    "",
    "## Testing",
    "- [x] Unit tests for backoff timing and non-retryable errors",
    "- [x] Ran 200 tasks against a flaky origin URL",
    "- [ ] e2e in robot studio",
  },
  files = {
    { path = "packages/runner/src/task/retry.ts", status = "M", additions = 48, deletions = 12, threads = 2, viewed = false },
    { path = "packages/runner/src/task/runTask.ts", status = "M", additions = 9, deletions = 3, threads = 0, viewed = false },
    { path = "packages/runner/src/config.ts", status = "M", additions = 4, deletions = 0, threads = 1, viewed = false },
    { path = "packages/runner/test/retry.test.ts", status = "A", additions = 61, deletions = 0, threads = 0, viewed = true },
    { path = "docs/runner.md", status = "M", additions = 12, deletions = 2, threads = 0, viewed = false },
  },
  commits = {
    { sha = "a3f91c2", message = "Use config for retry limits" },
    { sha = "7be0d14", message = "Add exponential backoff" },
    { sha = "c21a9fe", message = "Skip retry on 4xx" },
    { sha = "0d8e3b7", message = "Add RetryExhaustedError" },
    { sha = "e44f1a0", message = "Tests for withRetry" },
    { sha = "91c7d52", message = "Document retry settings" },
  },
  checks = {
    { name = "lint", status = "pass", duration = "18s" },
    { name = "typecheck", status = "pass", duration = "41s" },
    { name = "unit / runner", status = "pass", duration = "1m 12s" },
    { name = "build", status = "pass", duration = "2m 03s" },
    { name = "e2e / robot-studio", status = "fail", duration = "6m 40s" },
  },
}

M.patch = [[
diff --git a/packages/runner/src/task/retry.ts b/packages/runner/src/task/retry.ts
--- a/packages/runner/src/task/retry.ts
+++ b/packages/runner/src/task/retry.ts
@@ -12,7 +12,11 @@ export async function withRetry<T>(task: () => Promise<T>, config: RetryConfig)
-  for (let attempt = 0; attempt < 3; attempt += 1) {
+  for (let attempt = 0; attempt < config.retry.maxAttempts; attempt += 1) {
     try {
       return await task()
     } catch (error) {
+      if (!isRetryable(error)) {
+        throw error
+      }
-      await sleep(1000)
+      const delay = baseDelayMs * 2 ** (attempt - 1)
+      await sleep(Math.min(delay, config.retry.maxDelayMs))
     }
   }
diff --git a/packages/runner/src/config.ts b/packages/runner/src/config.ts
--- a/packages/runner/src/config.ts
+++ b/packages/runner/src/config.ts
@@ -20,6 +20,10 @@ export type RunnerConfig = {
   concurrency: number
+  retry: {
+    maxAttempts: number
+    baseDelayMs: number
+    maxDelayMs: number
+  }
 }
]]

M.file_sources = {
  ["packages/runner/src/task/retry.ts"] = table.concat({
    "import { sleep } from \"./time\"",
    "import { isRetryable } from \"./errors\"",
    "",
    "export interface RetryConfig {",
    "  maxAttempts: number",
    "  baseDelayMs: number",
    "  maxDelayMs: number",
    "}",
    "",
    "export async function withRetry<T>(task: () => Promise<T>, config: RetryConfig) {",
    "  // retry with bounded exponential backoff",
    "  for (let attempt = 0; attempt < config.retry.maxAttempts; attempt += 1) {",
    "    try {",
    "      return await task()",
    "    } catch (error) {",
    "      if (!isRetryable(error)) {",
    "        throw error",
    "      }",
    "      const delay = baseDelayMs * 2 ** (attempt - 1)",
    "      await sleep(Math.min(delay, config.retry.maxDelayMs))",
    "    }",
    "  }",
    "  throw new Error(\"retry exhausted\")",
    "}",
  }, "\n"),
  ["packages/runner/src/config.ts"] = table.concat({
    "export type RunnerConfig = {",
    "  concurrency: number",
    "  retry: {",
    "    maxAttempts: number",
    "    baseDelayMs: number",
    "    maxDelayMs: number",
    "  }",
    "}",
  }, "\n"),
}

M.threads = {
  {
    id = 1,
    path = "packages/runner/src/task/retry.ts",
    line = 14,
    resolved = false,
    comments = {
      {
        author = "dev-lee",
        age = "1h ago",
        body = "attempt is already incremented here, so the first retry waits 2x base. Intended?",
      },
      {
        author = "sara-k",
        age = "40m ago",
        body = "Good catch, should be 2 ** (attempt - 1). Fixing in the next push.",
      },
    },
  },
  {
    id = 2,
    path = "packages/runner/src/config.ts",
    line = 9,
    resolved = false,
    comments = {
      {
        author = "dev-lee",
        age = "1h ago",
        body = "Can maxDelayMs be optional with a conservative default?",
      },
    },
  },
}

M.compare = {
  base = "main",
  head = "feat/monitor-diffs",
  ahead = 12,
  behind = 3,
  commits = {
    { sha = "9a7d3f0", message = "Track removed rows" },
    { sha = "52e81bc", message = "Index snapshot rows by key" },
    { sha = "d013a6e", message = "Add rowKey helper" },
    { sha = "7f2c9e4", message = "Monitor diff email template" },
  },
  files = {
    { path = "monitor/src/diff.ts", status = "M", additions = 44, deletions = 22, notes = 1 },
    { path = "monitor/src/rowKey.ts", status = "A", additions = 88, deletions = 0, notes = 0 },
    { path = "monitor/src/notify.ts", status = "M", additions = 31, deletions = 9, notes = 0 },
    { path = "monitor/templates/diff.mjml", status = "A", additions = 121, deletions = 0, notes = 0 },
    { path = "monitor/test/diff.test.ts", status = "A", additions = 0, deletions = 30, notes = 0 },
  },
  notes = 1,
}

M.keymap_groups = {
  {
    title = "Navigation",
    items = {
      { lhs = "j / k", description = "next / previous item" },
      { lhs = "]f / [f", description = "next / previous file" },
      { lhs = "]t / [t", description = "next / previous thread" },
      { lhs = "<CR>", description = "open selection" },
    },
  },
  {
    title = "Review",
    items = {
      { lhs = "r", description = "reply to thread" },
      { lhs = "R", description = "resolve or submit" },
      { lhs = "s", description = "suggest change" },
      { lhs = "v", description = "mark file viewed" },
    },
  },
  {
    title = "Windows",
    items = {
      { lhs = "za", description = "fold thread" },
      { lhs = "?", description = "toggle this help" },
      { lhs = "q", description = "close window" },
    },
  },
}

return M
