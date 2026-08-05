# Runtime UI extensibility in a packaged Tauri v2 app

Research date: 2026-08-05. Target: Hearth (`D:\Tools\Valinor\hearth-client`), Tauri v2 + React + TypeScript, signed installer.

Every factual claim below carries a URL. Claims marked **[doc]** come from documentation or source code. Claims marked **[practice]** come from a shipping application or a confirmed report. Claims marked **[inference]** are mine and are not directly sourced.

---

## Verdict

**Yes.** A packaged, signed Tauri v2 app can render UI that was defined after it shipped. Three mechanisms work, in descending order of confidence:

1. **Declarative spec, shipped renderer.** The model emits JSON, not code. The shipped bundle contains a renderer that walks the JSON and instantiates already-compiled React components. No new code is loaded, no CSP change, no signing question. A month grid with marked days is expressible this way. This is what Kunkun calls a "template" extension and what Figma's plugin API effectively is on the document side.
2. **Dynamic `import()` of a plain ESM file from disk via the asset protocol.** Tauri v2's asset protocol serves `.js` and `.mjs` as `text/javascript` and sets `Access-Control-Allow-Origin` to the window origin, which is what a module fetch requires. This is documented and readable in the source; I found no confirmed public report of someone doing exactly this in v2, so treat it as **[doc]** until you test it. Requires `assetProtocol.enable: true` plus a scope, and a CSP that permits `asset:` / `http://asset.localhost` in `script-src`. Does **not** require `unsafe-eval`.
3. **Rust reads the file, webview evaluates the string.** The Tauri maintainer's own recommendation, and the fallback when the asset protocol path fails. Requires `unsafe-eval` if done from the frontend; does not, if done via `WebviewWindow::eval` from Rust, because that injects a script rather than calling `eval()` inside the page.

Signing is not a constraint on any of these. On both Windows and macOS, executing JavaScript out of a user-writable directory does not touch, alter, or invalidate the application's code signature. The only place it becomes a policy problem is the Mac App Store, which Hearth is not shipping through.

The real engineering constraints are: getting React across the boundary to a module that was not bundled with it; compiling TSX to JS somewhere other than the user's machine; and choosing an isolation boundary. The real policy choices are: CSP strictness, whether to sandbox, and whether to show the user the generated code before running it.

---

## Loading code at runtime

### The asset protocol

Tauri v2 serves files from disk into the webview through the `asset:` custom protocol, addressed from the frontend through `convertFileSrc`. **[doc]** https://v2.tauri.app/security/asset-protocol/

The URL form is platform-dependent. On macOS, iOS and Linux, custom protocols resolve as `<scheme>://localhost/<path>`. On Windows and Android they resolve as `http://<scheme>.localhost/<path>` by default, switchable to `https://` via `WebviewBuilder::use_https_scheme`. **[doc]** https://docs.rs/tauri/latest/tauri/struct.Builder.html#method.register_uri_scheme_protocol

`use_https_scheme` defaults to `false` on Windows and Android, and the Tauri commit adding it notes that the HTTPS variant will not allow mixed content and therefore will not match the `<scheme>://localhost` behavior on macOS and Linux. **[doc]** https://github.com/tauri-apps/tauri/commit/f37e97d410c4a219e99f97692da05ca9d8e0ba3a

Two facts from the asset protocol implementation matter for module loading:

- **Content-Type.** The handler parses the MIME type from magic bytes plus the path and sets `Content-Type` on the response. **[doc]** https://github.com/tauri-apps/tauri/blob/dev/crates/tauri/src/protocol/asset.rs The extension table maps both `.js` and `.mjs` to `text/javascript`. **[doc]** https://docs.rs/tauri-utils/latest/src/tauri_utils/mime_type.rs.html A module fetch is rejected outright by every browser engine if the MIME type is not a JavaScript type, so this is load-bearing.
- **CORS.** The same handler sets `Access-Control-Allow-Origin` to the window origin on every response. **[doc]** https://github.com/tauri-apps/tauri/blob/dev/crates/tauri/src/protocol/asset.rs

That second point retires the objection you will find in the most-cited discussion on this topic. In 2021, a developer trying to build exactly this kind of plugin system in Tauri v1 hit `Cross origin requests are only supported for protocol schemes: http, data, chrome-extension, edge, https, chrome-untrusted`. **[practice]** https://github.com/orgs/tauri-apps/discussions/2820 On Windows in v2 the custom protocol *is* `http://asset.localhost`, and the handler now emits an ACAO header. The 2021 failure mode does not describe v2 on Windows. I did not find anyone confirming this in writing, so verify it before building on it.

### Configuration required

`assetProtocol.enable` defaults to `false` and `assetProtocol.scope` defaults to `[]`. **[doc]** https://v2.tauri.app/reference/config/ Both must be set. Paths resolved at runtime must match the scope or the webview refuses the load with "asset protocol not configured to allow the path". **[doc]** https://v2.tauri.app/security/asset-protocol/

Scope is a `FsScope`: either an array of glob patterns or an object with `allow`, `deny`, and `requireLiteralLeadingDot`. **[doc]** https://v2.tauri.app/reference/config/ For Hearth, an allow entry covering `$APPDATA/cards/**/*.js` and a `deny` on everything else is the shape you want. Note that scopes chosen at runtime through a dialog do not survive restart unless you use the persisted-scope plugin; a *statically configured* scope in `tauri.conf.json` is not affected by this. **[doc]** https://github.com/tauri-apps/tauri/issues/13788

Hearth's current config, for reference, has neither `assetProtocol` nor a CSP: `D:\Tools\Valinor\hearth-client\src-tauri\tauri.conf.json` contains only `"security": { "csp": null }`.

### Custom protocol of your own

`Builder::register_uri_scheme_protocol` lets you serve arbitrary app-generated bytes to the webview under a scheme you name, backed by `setURLSchemeHandler` on macOS, `AddWebResourceRequestedFilter` on Windows, and `webkit_web_context_register_uri_scheme` on Linux. **[doc]** https://docs.rs/tauri/latest/tauri/struct.Builder.html#method.register_uri_scheme_protocol You control the response headers, so you control `Content-Type` and `Access-Control-Allow-Origin` directly.

This is strictly more flexible than the asset protocol and is the mechanism I would reach for if the asset protocol proves awkward: a `card://` scheme whose handler validates the card ID, reads from a directory only Rust knows about, and returns `text/javascript`. It also gives you a natural place to enforce a manifest, a hash check, or an allowlist, which the asset protocol does not.

Kunkun, the Tauri v2 Raycast alternative, uses `register_uri_scheme_protocol` for its extension content. **[practice]** https://github.com/kunkunsh/tauri-api-adapter

### Fetch-and-evaluate

The Tauri maintainer's recommendation in discussion #2820 was: "acquire the path in rust, read the file in rust, then eval it in the webview by rust." **[practice]** https://github.com/orgs/tauri-apps/discussions/2820 The same thread records a maintainer warning that an unguarded version of this "is REALLY asking for your app to get pwned" and that "any vulnerability in any plugin can potentially compromise everything."

A variant that keeps the frontend in control: a Tauri command returns the file contents as a string, the frontend wraps it in a `Blob` with type `text/javascript`, and `import()`s the resulting blob URL. This is a real module import, not `eval`, so it does not need `unsafe-eval`; it needs `blob:` in `script-src`, which is a broad grant (see CSP below).

A request for dynamic plugin loading as a first-class Tauri feature was filed and **closed as not planned**. **[doc]** https://github.com/tauri-apps/tauri/issues/8090 There is no built-in Tauri primitive for this. Everything above is assembled from parts.

### The two problems nobody's docs mention

Both are **[inference]**, and both will bite before CSP does.

1. **Bare specifiers.** A runtime-loaded module cannot `import React from "react"` because there is no bundler and no resolver. Two fixes. An import map declared in `index.html` mapping `react` to a bundled chunk works, but the map must be present before any module loads and cannot be extended afterwards. The more robust option is a factory contract: the generated module default-exports a function that receives the host's React, the host's component primitives, and the card data, and returns an element. The module then has zero imports and the host controls the entire surface it can reach.
2. **TSX does not run.** Whatever the model writes has to become plain JavaScript before it reaches the webview. Compiling on the user's machine means shipping a compiler and paying for `unsafe-eval` or `blob:`. Compiling on the Valinor side, where esbuild already exists, means the file that lands on disk is already plain ESM. That is the same trade Figma made when it moved compilation out of the client, and it is the reason option 2 in the verdict does not need `unsafe-eval`.

---

## CSP

### What Tauri gives you by default

Nothing. `csp` and `devCsp` both default to null. **[doc]** https://v2.tauri.app/reference/config/ The docs are explicit: "The CSP protection is only enabled if set on the Tauri configuration file." **[doc]** https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/security/csp.mdx The `create-tauri-app` scaffold ships `"csp": null`, which is why Hearth has it.

So "setting it to null" is not a change. It is the state Hearth is already in, and it means the webview will load scripts, styles and resources from any origin. Adding a CSP is a hardening step you have not yet taken; runtime card loading is a good reason to take it, not a reason to avoid it.

When a CSP *is* set, Tauri appends its own nonces and hashes to the relevant directives at compile time for bundled code and assets, so you only write the application-specific parts. **[doc]** https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/security/csp.mdx `dangerousDisableAssetCspModification` defaults to `false` and controls whether that automatic modification happens. **[doc]** https://v2.tauri.app/reference/config/

### IPC interaction

Tauri's IPC needs an explicit grant. The documented example is `"connect-src": "ipc: http://ipc.localhost"`. **[doc]** https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/security/csp.mdx If you turn a CSP on without that directive, `invoke` breaks. This is the single most common way people break a working Tauri app by adding a CSP.

### What runtime module loading actually needs

For the asset-protocol path, a policy along these lines:

```
default-src 'self' ipc: http://ipc.localhost;
script-src 'self' asset: http://asset.localhost;
img-src 'self' asset: http://asset.localhost data:;
```

The documented asset-protocol CSP example is `"default-src 'self' ipc: http://ipc.localhost; img-src 'self' asset: http://asset.localhost"`; extending it to `script-src` is the same pattern. **[doc]** https://v2.tauri.app/security/csp/

### Is `unsafe-eval` avoidable

**Yes, and this is the most useful single finding in this section.** A dynamic `import()` of a URL is a script fetch, governed by `script-src` source expressions. It is not evaluation of a string and is not governed by `unsafe-eval`. `unsafe-eval` is only needed for `eval()`, the `Function` constructor, and `setTimeout` with a string body. **[doc]** https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src

So: if the card arrives on disk as already-compiled ESM and you `import()` it by URL, you can run a strict CSP with no `unsafe-eval` at all. If you compile TSX in the webview, or build components with `new Function`, you cannot.

`blob:` in `script-src` is the middle option and it is weaker than it looks. Blob URLs cannot be allowlisted by host or hash and are opaque, so allowing `blob:` is a blanket permission for any script already on the page to load arbitrary code. **[doc]** https://centralcsp.com/articles/csp-blob-scheme It is not as bad as `unsafe-eval`, but it is close, and it buys you nothing over the asset protocol if the file is on disk anyway.

Note that CSP is enforced by the webview engine, so behavior differs between WebView2 on Windows and WKWebView on macOS. I did not find a Tauri-specific writeup of those differences. **[gap]**

---

## Signing and notarization

### Windows

Authenticode hashes the contents of the PE file, omitting only the header checksum, the certificate table directory entry, and the certificate table itself. **[doc]** https://learn.microsoft.com/en-us/windows/win32/secbp/understanding-pe-signatures and the format specification at https://www.symbolcrash.com/wp-content/uploads/2019/02/Authenticode_PE-1.pdf

The signature covers the executable file. It does not cover, and has no opinion about, files the running process later reads from `%APPDATA%`. Writing a `.js` into the app's data directory and loading it does not alter any signed byte and cannot invalidate the signature. **[inference]**, but it follows directly from what the hash is computed over.

SmartScreen reputation attaches to the signed binary and its certificate. **[doc]** https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options Nothing in the reputation model inspects runtime file reads.

There is no operating-system-level distinction on Windows between "data" and "executable code" for a file that is never mapped as an executable image. A `.js` file read by your process and handed to a webview is data as far as Windows is concerned. It is only executable in the sense that your app chose to interpret it. **[inference]**

### macOS

Gatekeeper verifies at launch that the software is from an identified developer, is notarized, and has not been altered. **[doc]** https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web "Has not been altered" means the app bundle's sealed resources. A file in `~/Library/Application Support/` is not part of the bundle and is not sealed. **[inference]**

Hardened runtime is the entitlement question, and it is narrower than it sounds. Under hardened runtime, "every single executable page within your address space must be backed by the original code signature that shipped with your app." **[doc]** https://twocanoes.com/apple-ramps-up-fight-against-malware-with-notarization-stapling-and-hardening/ That constrains Mach-O pages, not interpreted JavaScript.

WKWebView renders out of process: "WKWebView's dynamically generated code is running safely firewalled in a separate address space controlled by Apple and not accessible to your app." **[doc]** https://developer.apple.com/forums/thread/713926 JavaScript JIT happens in Apple's own signed WebContent process, not in yours.

The caveat: `com.apple.security.cs.allow-jit` is reported as required on Apple Silicon for applications embedding WKWebView or JavaScriptCore. **[doc]** https://qatools.knowledgebase.qt.io/squish/mac/troubleshoot/hardened-runtime/ If Hearth already ships a working notarized macOS build with a webview, this is already resolved and runtime card loading changes nothing about it. If it does not yet ship on macOS, this is a baseline webview requirement and not something runtime cards introduce. **[inference]**

Library validation, which restricts loading unsigned dylibs, is about Mach-O loading and does not apply. **[inference]**

### The one place it is a real constraint

Mac App Store. Guideline 2.5.2: "Apps should be self-contained in their bundles, and may not read or write data outside the designated container area, nor may they download, install, or execute code which introduces or changes features or functionality of the app." The only carve-out is for educational apps that teach coding, and it requires the source be fully viewable and editable by the user. **[doc]** https://developer.apple.com/app-store/review/guidelines/

That guideline would be a genuine problem for a card system distributed through the Mac App Store. It has no bearing on Developer ID plus notarization, which is how Obsidian, VS Code, and every Electron plugin host ship. **[inference]**

**Summary: signing is a policy choice, not an engineering constraint, unless you want the Mac App Store.**

---

## Precedent

### Obsidian: the closest analogue, and the least sandboxed

Obsidian is a signed, notarized, shipping Electron app that loads arbitrary third-party JavaScript at runtime, and its answer to sandboxing is: there isn't one.

Plugins are a `manifest.json` plus a compiled `main.js`, living in `.obsidian/plugins/<id>/` inside the user's vault. Obsidian executes `main.js` at runtime and calls its `onload()`. **[practice]** https://docs.obsidian.md/Plugins/Getting+started/Build+a+plugin Multiple independent writeups describe the loading mechanism specifically as `eval`. **[practice]** https://deepwiki.com/obsidianmd/obsidian-developer-docs/2.1-getting-started-with-plugin-development and https://mnaoumov.wordpress.com/2022/05/10/how-to-debug-obsidian-plugins/ I did not find a first-party Obsidian statement naming `eval`, so the mechanism is confirmed by convergent third-party reporting rather than by Obsidian. **[gap]**

The official security page is blunt about the consequences. Obsidian "cannot reliably restrict plugins to specific permissions or access levels," so "plugins will inherit Obsidian's access levels." Community plugins can access files on your computer, connect to the internet, and install additional programs. **[practice]** https://github.com/obsidianmd/obsidian-help/blob/master/en/Extending%20Obsidian/Plugin%20security.md

This is possible because Obsidian's renderer has node integration; plugins `require('fs')` and `require('electron')` directly, and such plugins are marked `desktopOnly`. **[practice]** https://github.com/GitMurf/obsidian-api

What Obsidian does instead of a sandbox is **consent plus review**:

- **Restricted Mode is on by default.** Third-party code does not execute until the user turns it off. Installed plugins remain in the vault and are ignored. **[practice]** https://github.com/obsidianmd/obsidian-help/blob/master/en/Extending%20Obsidian/Plugin%20security.md
- **An explicit trust statement.** "Only disable Restricted mode if you trust the authors of the plugins that you install." Same source.
- **Automated scanning and safety scorecards** on each plugin's directory page, with community reporting, because the team is too small to manually review every release. Same source.

The transferable lesson for Hearth: Obsidian's security model is a *default-off switch plus an honest disclosure*, not a technical boundary. If that is acceptable for arbitrary code written by strangers on the internet, a default-off switch is defensible for code written by a model at the user's own request. The disclosure has to be equally honest.

### VS Code: process isolation without a security boundary

Extensions run in dedicated Extension Host processes, separate from the renderer and main processes, each an isolated Node.js runtime communicating over a JSON-RPC-like protocol. **[practice]** https://code.visualstudio.com/blogs/2022/11/28/vscode-sandbox

But process separation here is about renderer sandboxing and stability, not about containing extensions. All extensions in a host share memory and Node global state; `fs`, `http` and `child_process` are not compartmentalized per extension and can be monkey-patched by any extension in the same host. **[practice]** https://nhsjs.com/2025/automated-security-framework-for-vs-code-extensions-risk-profiling-policy-generation-and-runtime-sandboxing/

The part that *is* relevant to Hearth is the UI side: extension-contributed UI does not run in the editor's page. It runs in a webview, which VS Code moved from Electron's `webview` tag to a plain `iframe` during the sandboxing migration. **[practice]** https://code.visualstudio.com/blogs/2022/11/28/vscode-sandbox That is the same split Hearth would want: extension logic somewhere contained, extension pixels in an iframe.

### Figma: the one that actually solved it, twice

Figma is the most instructive precedent because they solved exactly this problem for genuinely untrusted UI code, got it wrong, and published the correction.

Version one used the Realms shim to sandbox plugin JavaScript in the browser's own VM. It performed well and debugged well in DevTools. It also had escapes: the shim could confuse an object from outside the sandbox with one from inside, which is possible precisely because the same JavaScript VM runs both sandboxed and host code. **[practice]** https://www.figma.com/blog/an-update-on-plugin-security/

Version two replaced it with QuickJS, a JavaScript VM written in C and cross-compiled to WebAssembly. Objects inside the WASM runtime are represented differently from browser objects, which makes the confusion class of escape infeasible rather than merely patched. **[practice]** Same source.

They paid for it: some plugins run "somewhat slower," and developers lose browser DevTools. Figma judged both acceptable. **[practice]** Same source.

The resulting architecture is a split: plugin logic runs in QuickJS with access to the document API, plugin UI runs in an iframe. **[practice]** https://macwright.com/2024/03/29/figma-plugins

### Tauri: thin, but not empty

Tauri is younger and there is much less here. The one substantial example I found is **Kunkun**, a cross-platform extensible app launcher listed in `awesome-tauri`. **[practice]** https://github.com/tauri-apps/awesome-tauri

Kunkun runs extensions in **iframes and Web Workers as sandboxed extension runtimes**, with two distinct extension shapes: "custom" extensions that own an iframe and render their own UI, and "template" extensions that run in a Web Worker and describe UI that the host renders. **[practice]** https://docs.kunkun.sh/developer/api/ui/iframe/ Communication is kkRPC, a JSON-RPC-like bidirectional protocol spanning iframe, Web Worker, stdio, HTTP and WebSocket, with callback support. **[practice]** https://github.com/kunkunsh/kkrpc

The most interesting piece for Hearth is `tauri-api-adapter`, which exists because "Tauri 2 hard codes permissions for each window during compilation" and therefore cannot express per-extension permissions for dynamically loaded content. The adapter adds runtime permission control per iframe and per worker. **[practice]** https://github.com/kunkunsh/tauri-api-adapter That is a direct statement that Tauri v2's capability system does not, on its own, solve permissioning for runtime-loaded UI. You either build that layer or you do without it.

Also worth knowing: `tauri-plugin-js`, from the same author, spawns and manages Bun/Node/Deno processes from a Tauri app for backend extension code. **[practice]** https://github.com/HuakunShen/tauri-plugin-js Not the right shape for a UI card, but the right shape if a card ever needs to compute.

Kunkun's "template" model is the same thing as verdict option 1, and it is notable that a Tauri app that could have chosen arbitrary code execution for its simple extensions chose a host-rendered declarative model instead.

---

## Sandboxing

### Iframes

A `sandbox`ed iframe is the standard boundary and the one both Figma and Kunkun use for plugin UI. **[practice]** https://macwright.com/2024/03/29/figma-plugins, https://docs.kunkun.sh/developer/api/ui/iframe/ It was also suggested in the Tauri discussion, specifically `srcdoc` plus `sandbox` plus `postMessage`. **[practice]** https://github.com/orgs/tauri-apps/discussions/2820

**There is a Windows-specific problem you must know about.** Tauri's own Isolation pattern, which is built on a sandboxed iframe, documents that external files do not load correctly inside sandboxed iframes on Windows, which forces scripts to be inlined at build time and means ES modules will not load. **[doc]** https://v2.tauri.app/concept/inter-process-communication/isolation/ Hearth is a Windows-first product. Any iframe design has to be validated against WebView2 specifically, and the safe assumption is that you will be passing card source in as a string via `srcdoc` or `postMessage` rather than pointing the iframe at a file URL. **[inference]**

The integration cost is the real cost. Everything crosses `postMessage`: no shared React tree, no shared theme object, no shared component instances, structured-clone-only data, and asynchronous everything. A card rendered in an iframe cannot participate in Hearth's layout, cannot inherit its CSS, and needs an explicit resize protocol. For a calendar card this is survivable. For a card that wants to look native inside the shell, it is a visible seam.

### QuickJS compiled to WebAssembly

This is proven in production for the *logic* half of a plugin system. Figma runs it for every plugin. **[practice]** https://www.figma.com/blog/an-update-on-plugin-security/ `quickjs-emscripten` is the mature JavaScript binding, with memory and stack caps for untrusted code. **[practice]** https://www.npmjs.com/package/quickjs-emscripten

It is **not** used in production for rendering UI, and cannot be directly. QuickJS-in-WASM has no DOM. A card running there can compute a description of what to draw, which the host then renders. That is Figma's exact architecture, and it collapses back into verdict option 1 with a scripting layer added.

The escape hatches are the usual ones: isolation holds only as far as the host objects you inject. The `quickjs-emscripten` maintainers warn explicitly that exposing the host `fetch` hands the guest your cookies and must not be done for untrusted code. **[practice]** https://www.npmjs.com/package/quickjs-emscripten One React-oriented experiment exists, `react-quickjs-sandbox`. **[practice]** https://github.com/jabinb/react-quickjs-sandbox I did not evaluate its maturity and would not assume it is production-ready. **[gap]**

Rough judgment: this is the strongest boundary available and it is disproportionate for locally generated, user-requested cards. It is what you would reach for if Hearth ever gained a card marketplace. **[inference]**

### Web Workers

Weaker than an iframe for this purpose. A worker has no DOM, so it is a logic sandbox, not a UI sandbox, which puts it in the same category as QuickJS but with a much thinner boundary: same JavaScript engine, same process in most cases, no memory caps. Its advantage is that it is free and built in. Kunkun uses workers exactly this way, for template extensions whose UI the host renders. **[practice]** https://docs.kunkun.sh/developer/api/ui/iframe/ A worker also inherits the creating document's CSP when created from a blob or data URL. **[doc]** https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src

### What the threat model actually justifies

The code is generated locally, by a model the user is running, at the user's own request. There is no marketplace, no author, no network fetch. That removes the entire supply-chain half of the threat model that Obsidian and Figma are built around.

What it does not remove: a model can be steered by content it reads, and a card with full access to the host page has full access to Hearth's IPC surface, which reaches Rust, which reaches the filesystem. If Hearth ever renders a card built from text that arrived from outside (an email, a web page, a shared document), the generated card is downstream of untrusted input even though the generator is local. **[inference]**

The proportionate answer, in order: constrain what a card *can* express (option 1 removes the question entirely); if cards must be code, give them a factory signature with an explicit injected API and no ambient imports; put a strict CSP in place with no `unsafe-eval`; keep the generated source viewable, because the user asked for it and Obsidian's own guidance is that review is the mitigation of last resort. Reach for iframes when a card can be built from untrusted content, and for QuickJS only if cards ever become shareable.

---

## What I could not determine

- **Whether `import()` from `asset:` actually works in a packaged Tauri v2 app.** Every documented precondition is satisfied (`text/javascript` Content-Type, `Access-Control-Allow-Origin` set to the window origin), but I found no confirmed report of anyone doing it in v2, on either platform. The one detailed public account is the v1-era CORS failure in discussion #2820. This needs a ten-minute experiment before any design depends on it, and it needs to be run on Windows/WebView2 and macOS/WKWebView separately.
- **Whether Tauri's asset protocol handler is reached for module fetches at all**, or whether WebView2's `AddWebResourceRequestedFilter` intercepts module requests the same way it intercepts document and subresource requests. **[gap]**
- **A first-party Obsidian statement that plugins are loaded via `eval`.** Confirmed by several independent third-party sources; not stated in Obsidian's own docs, which describe only that `main.js` is "the compiled version of the plugin that Obsidian executes."
- **Whether the Tauri maintainers gave a reason for closing #8090 as not planned.** The issue page renders without visible comments through fetch.
- **Concrete CSP behavior differences between WebView2 and WKWebView** under Tauri, particularly for `script-src` with custom protocol sources. No Tauri-specific documentation found.
- **Whether `com.apple.security.cs.allow-jit` is genuinely required for a notarized Tauri app on Apple Silicon**, or whether that requirement applies only to in-process JavaScriptCore embedding. The Squish knowledge base states it is required for WKWebView; the Apple forums thread states WKWebView JIT happens in Apple's separate process. These are in tension and I could not resolve them. Check whether Hearth's existing macOS build, if any, already carries the entitlement.
- **The maturity of `react-quickjs-sandbox`** or of any production system rendering React from inside a WASM JavaScript VM. I found the project; I did not assess it.
