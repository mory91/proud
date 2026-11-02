# Thread Window

The review threads on one diff line, in full, in a rounded float beside that line, and the reply editor under them (design screen 4). The diff pane hosts it: `K` on a line with a `◆` / `◇` sign opens it.

## Reading

- One header per thread: `◆` / `◇`, file and line, unresolved / resolved, comment count, and `outdated` when GitHub marks it so. The commented line is quoted under the first header.
- Every comment in full: author, age, and the body wrapped to the window, paragraphs kept. Replies are indented with `↳`. The pull request's author is tagged `author`; comments in your pending review are tagged `pending`.
- It opens without focus; `K` again focuses it to scroll. `q` / `<Esc>` close it and return to the line. Moving off the line, Insert mode in the diff, switching files, leaving it for another window or closing the page close it.
- It opens below the line, or above it when there is more room.

## Replying

- `r` in the window opens the reply editor under the thread (the thread under the cursor when several share the line), focused and in Insert mode. The thread window adds `Reply as <login> · markdown · @ mention  <C-g> insert suggestion`.
- The editor is a markdown buffer that grows with its text (3 to 10 rows). `@` offers the thread's participants and the pull request's author. `<C-g>` inserts a ```` ```suggestion ```` block with the commented line.
- `<C-s>` posts the reply. `<C-r>` posts it and resolves the thread. `<C-p>` adds it to your pending review (starting one if needed), which `R` on the overview submits. `<Esc>` closes the editor and keeps the draft; drafts are kept per thread while the page is open, and also when the window closes.
- `R` in the window resolves the thread without a reply.
- While posting, the window says so. A failed post shows GitHub's message under the reply header, notifies it, and keeps the editor and its text. Empty replies are not posted.

## Host contract

`open(host, options)` takes the diff window and line, the threads on it, the line's text, the PR author, a `viewer()` getter, a shared `drafts` table and `act(kind, thread, body, done)` for `post`, `resolve`, `pending` and `resolve_only`. The diff pane maps `act` to the session (GitHub REST replies under the thread's top comment, GraphQL `resolveReviewThread`, `addPullRequestReviewThreadReply` into a pending review); without a host action, replies stay local (demos, plain compares).

## Related Code

- `feature.lua` implements the text (`view`), layout, editor, keys and cleanup.
- `tests/unit_spec.lua` verifies the text: quoted line, tags, wrapping, reply header and errors, mention candidates.
- `tests/e2e_spec.lua` drives a real window: placement, focus, the editor, drafts, posting, failure, pending, post and resolve, resolve, closing and buffer cleanup.
- `bench/benchmark.lua` enforces the text SLA for a 50-comment thread.
