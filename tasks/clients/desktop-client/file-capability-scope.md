---
area: clients/desktop-client
status: open
depends_on: []
blocks: []
updated: 2026-08-26
---

# The desktop client claims file access it may not have

`src/lib/clientProfile.ts:17` declares the capability set unconditionally:

```ts
export const CLIENTS: Record<ClientId, { label: string; has: Capability[] }> = {
  desktop: { label: 'Hearth desktop', has: ['files', 'window', 'inapp-theme', 'devpane'] },
  ...
};
export const CLIENT_ID: ClientId = 'desktop';
```

Every desktop client says it has `files`. Nothing asks whether the house it is
talking to is on the same machine.

## Why that is wrong

The harness offers a session its tools as `enabled ∩ persona grants ∩ client
capabilities`. The `files` capability is what makes `read_file`, `list_dir`,
`write_file` and `open_path` reachable. Those tools operate on the **house's**
filesystem.

When the house is local, that is the same disk the person is looking at and
everything is coherent. When the house is remote, and Settings explicitly
supports pointing at a hostname or a tailnet name, the client still claims
`files`, so the persona is offered tools that read and write a filesystem the
person is not sitting in front of. `open_path` is the sharpest case: it asks
the local shell to open a path that exists on a different computer.

`isTauri()` already exists in the same file and correctly hides those rows in a
browser tab. The same reasoning has not been applied to the remote case.

## The second half: path translation is Windows and WSL only

`src/lib/openPath.ts` translates `/mnt/<drive>` POSIX paths into Windows drive
letters, because Valar used to run in WSL. That is the whole of it:

- No macOS handling, though the macOS alpha ships and its paths are already
  POSIX and already correct, so translating them would break them.
- No same-host check before handing the path to the shell.

WSL is being sunset, so the translation this function exists for is on its way
out while the case it does not handle is on its way in.

## What to decide

1. **How the client learns whether the house is local.** The address is in
   Settings; comparing it against loopback is the cheap version and is probably
   enough. A more honest answer is for the house to say so in `client_info`,
   since it knows.
2. **Whether `files` becomes conditional or the tools get a guard.** Dropping
   the capability is cleaner: it removes the tools from the offered set rather
   than letting them be called and fail.
3. **What `open_path` does on a remote house.** Refusing is defensible.
   Offering to reveal the path in the house's own file browser is better, and
   is a different feature.

## Provenance

Found 2026-08-26 by an audit of Valinor's `tasks/desktop-client-macOS.md`,
which listed "same-host `files` capability detection" as item 4 and never built
it. That document has been archived because the macOS port itself shipped; this
is the one item that outlived it, and it belongs here rather than in Valinor,
because the desktop client is Hearth's now.

## Related

- [_index.md](_index.md), and note that the client which builds the binary is
  the Valinor copy, so a fix has to land there too.
