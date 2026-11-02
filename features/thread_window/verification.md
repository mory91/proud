# Verification

Unit tests must cover the thread text: the quoted line, author and pending tags, outdated and resolved states, wrapping within the window width, the reply header with the viewer (or "you"), error lines, and mention candidates (participants and author once, never the viewer).

E2E tests must open the window in a real Neovim window and prove: it opens unfocused and anchored to the line (above it near the bottom); `r` opens a focused markdown editor right next to the thread; `<C-g>` inserts a suggestion with the line; `<Esc>` keeps the draft and returns to the thread; `r` restores the draft; `<C-s>` posts and adds the reply; a failed post shows and notifies GitHub's message and keeps the text; `<C-p>` adds a pending reply; `<C-r>` posts and resolves; empty replies are refused; `R` resolves; `q`, leaving the window and moving off the line close it, keep drafts and wipe its buffers.

Integration: the diff pane test replies through `K`, `K`, `r` with the local fallback and shows the pending count in the window bar. The compare page test posts through the session to a fake GitHub client (reply under the top comment as the signed-in user, resolve by thread id) and the sidebar's thread count follows. The real-terminal suite must show the reply editor on screen and post a reply.
