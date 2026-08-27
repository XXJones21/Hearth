---
area: clients/desktop-client
updated: 2026-08-26
---

# The desktop client -- the backlog

What the Tauri desktop client still owes. Same convention as the other client
folders: one file per area, not per change, and every file states its status in
its own frontmatter.

## Open

| Area | What it is | Status |
| --- | --- | --- |
| [layout-modes.md](layout-modes.md) | A toggle between the current workstation shell and a phone-shaped one. | open |
| [speech-input.md](speech-input.md) | The client speaks and cannot hear. | open |
| [file-capability-scope.md](file-capability-scope.md) | It claims `files` even when the house is on another machine. | open |

The two are related rather than ordered: a conversational layout whose input is
text-only is honest but thin, so they are worth sequencing together.

## Where the client lives, which is worth writing down

The one that runs is built from **`D:/Tools/Valinor/hearth-client`**, and its
binary is `src-tauri/target/release/app.exe`. There is a second copy of the same
tree at `D:/Tools/Hearth/desktop-client`, and the two have drifted in both
directions: the Hearth copy carries a `min-h-0` fix on the persona rail that
Valinor lacks, and the Valinor copy carries a `PersonaCanvas` comment the Hearth
one dropped.

This cost real time on 2026-08-26: three rounds of flame tuning were made
against the Hearth copy, rebuilt nothing, and were judged on a binary from
2026-08-20. A client change needs a client rebuild, and it needs to be made in
the tree the binary is built from.
