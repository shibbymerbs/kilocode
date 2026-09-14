# Remove telemetry from the Kilo fork + rebuild the .vsix

Goal: strip the entire telemetry subsystem (PostHog + all wiring) from this repo, then build a local `.vsix` (Windows x64) that phones home to no one. The user runs local models (LM Studio); no Kilo-hosted services are needed.

## Decisions (agreed with user)

- **Full code removal** of the telemetry subsystem (user's explicit choice over a minimal no-op disable).
- **Keep** Kilo cloud *features* (Kilo gateway provider, cloud sessions, marketplace, profile/balance). They only fire when the user actively chooses a Kilo-hosted service; they are not telemetry.
- **Rebuild** the `.vsix` for local install (target `win32-x64`, the user's machine).

## Telemetry map (verified)

Unconditional telemetry (removal targets):

1. `packages/kilo-telemetry/` — PostHog client. `src/client.ts` has the hardcoded key `phc_GK2Pxl0HPj5ZPfwhLRjXrtdz8eD7e9MKnXiFrOqnB6z` and host `https://us.i.posthog.com`. `src/identity.ts` also phones home to `api.kilo.ai/api/profile` via `fetchProfile(token)` to resolve the user's email (telemetry identity only).
2. CLI bootstrap wiring — `packages/opencode/src/kilocode/cli/setup.ts`: `Telemetry.init`, `updateIdentity`, `trackCliStart`, `flushInBackground`, `trackCliExit`, `Telemetry.shutdown`.
3. ~15 `Telemetry.track*` call sites (see Phase 1 step 8).
4. Server endpoints — `POST /telemetry/capture`, `POST /telemetry/setEnabled`: `packages/opencode/src/kilocode/server/httpapi/groups/telemetry.ts` + `handlers/telemetry.ts`, registered in `src/kilocode/server/httpapi/server.ts:31,52` and `src/server/routes/instance/httpapi/api.ts:46` (shared upstream file).
5. SDK — generated telemetry client methods in `packages/sdk/js/src/gen|v2/gen` (regenerate, never hand-edit).
6. VS Code extension — `src/services/telemetry/` (proxy, types, utils, webview-state, errors), `TelemetryProxy` call sites (extension.ts, KiloProvider, MarketplacePanelProvider, agent-manager fork-session.ts / vscode-host.ts, AutocompleteServiceManager), `AutocompleteTelemetry` class + injections, webview senders (feedback.tsx, MarketplaceView.tsx, KiloNotifications.tsx, work-style.tsx, SidebarTopBar.tsx, AboutKiloCodeTab.tsx), `webview-ui/agent-manager/telemetry.ts` (tracker), message types `TelemetryRequest`/`telemetryState`, `KILO_TELEMETRY_LEVEL` env in `server-manager.ts:157`.
7. `script/stats.ts` (repo root) — PostHog download-stats at CLI install time (`sendToPostHog` to `us.i.posthog.com`).

Non-telemetry that must be preserved:

- `Identity.getMachineId()` is used for **functional** purposes in 2 places: `src/session/llm/request.ts:186` (Kilo provider `HEADER_MACHINEID` attribution header) and `src/kilocode/bootstrap.ts:62` (session-export `anonId`). Extract a minimal machine-ID helper **before** deleting the package.
- `KiloAgent.telemetryOptions` (`kilocode/agent/index.ts:464`) already returns `{ isEnabled: false }`; the `experimental_telemetry` block at `src/agent/agent.ts:552-554` is a removable kilocode_change block (removing it shrinks the fork diff).
- `tests/setup/vscode-mock.ts` `isTelemetryEnabled` — VS Code API mock, harmless, keep.
- `RecentlyVisitedRangesService.initWithPostHog` — misnamed, no PostHog usage, no network. Leave.

## Phase 1 — CLI core (`packages/opencode/`, `packages/kilo-telemetry/`)

1. Create `packages/opencode/src/kilocode/machine-id.ts` (Kilo-owned path, no markers): `export async function getMachineId(): Promise<string | undefined>` with a module-level cache. Behavior copied from `identity.ts:getMachineId`: `KILO_MACHINE_ID` env override, else read-or-create `<Global.Path.data>/telemetry-id` (UUID). Import `Global` from `@opencode-ai/core/global`.
2. `src/session/llm/request.ts`: replace `import { Identity } from "@kilocode/kilo-telemetry"` with the new helper; `Identity.getMachineId()` → `getMachineId()`. Keep the whole `kilocode_change` kilo-provider header block (lines 180-189, 249-256).
3. `src/kilocode/bootstrap.ts`: same replacement at line 62 (`Identity.getMachineId()`), drop the import.
4. Delete the `packages/kilo-telemetry/` directory entirely (incl. tests).
5. Remove `@kilocode/kilo-telemetry` from `packages/opencode/package.json` dependencies (verify exact entry).
6. `src/kilocode/cli/setup.ts`: delete the telemetry import + `Telemetry.init(...)`, `Telemetry.updateIdentity(...)`, `Telemetry.trackCliStart()`, `Telemetry.flushInBackground()` (bootstrap) and `Telemetry.trackCliExit(code)`, `await Telemetry.shutdown(2000)` (shutdown). Keep `SessionExport.shutdown()`, `KiloShutdown.run()`, and the `narrow` dispose logic. The `cfg` config fetch stays if still used elsewhere in that function (it is only used for the telemetry `enabled` flag — drop it too if unused, along with the `app`/`AppRuntime` config read it required; verify).
7. Delete `src/kilocode/server/httpapi/groups/telemetry.ts` and `handlers/telemetry.ts`. Remove registration: `src/kilocode/server/httpapi/server.ts:31,52`; `src/server/routes/instance/httpapi/api.ts:46` (shared upstream file — remove the import and its use in the group composition; keep remaining groups intact).
8. Remove `Telemetry` imports + all `track*` call sites (Kilo-owned files):
   - `src/kilocode/session/processor.ts` (`trackLlmCompletion` at :120, `trackStep` helper)
   - `src/kilo-sessions/kilo-sessions.ts` (:43 import + track calls)
   - `src/kilocode/tool/chart.ts`
   - `src/kilocode/suggestion/index.ts`
   - `src/kilocode/indexing.ts` (5 `trackIndexing*` calls)
   - `src/kilocode/cli/cmd/tui/feedback.ts`
   - `src/kilocode/plan-followup.ts`
   - `src/kilocode/review/command.ts` (`import type { ReviewCommand }`)
   - `src/kilocode/agent/index.ts` (`telemetryOptions`, :464)
   - `src/agent/agent.ts` — remove the `kilocode_change start/end` block around `experimental_telemetry` (:552-554) and the `KiloAgent` import if now unused (shared upstream file — this *removes* kilocode_change surface, good for merges)
   - `src/auth/index.ts` (:7 import + track calls) and `src/provider/auth.ts` (:13 import + track calls) — shared upstream files; remove the telemetry lines/marker blocks
   - `ReviewCommand` type: was defined in `kilo-telemetry/src/telemetry.ts`. After removal, define `type ReviewCommand = "review"` in `src/kilocode/review/command.ts` (or the module that owns it) and adjust the import in `kilocode/session/processor.ts` if it still references it.
9. Regenerate the SDK from repo root: `./script/generate.ts` (updates `packages/sdk/js/` gen files; removes telemetry methods). Commit the generated output.
10. Tests:
    - `test/kilocode/cli-shutdown.test.ts` — drop telemetry mocks/assertions (:25-26 area)
    - delete `test/kilocode/telemetry/feedback.test.ts`
    - `test/kilocode/suggestion/suggestion.test.ts`, `test/kilocode/plan-followup.test.ts` — remove `Telemetry` spies/assertions
    - `test/session/prompt.test.ts` — remove `Telemetry` import/usage
    - `test/kilocode/startup-speed.test.ts:51`, `test/kilocode/headless-session-drain.test.ts:66` — remove `KILO_TELEMETRY_LEVEL: "off"` env lines
11. Root `script/stats.ts`: remove `sendToPostHog` + its two `download` call sites (or delete the file if it does nothing else).
12. `bun install` at repo root (removes `posthog-node` + `@kilocode/kilo-telemetry` from `bun.lock`).
13. Grep-verify: `rg "kilo-telemetry|posthog|KILO_TELEMETRY_LEVEL"` across `packages/` (expect only benign hits: `test/mcp/auth.test.ts` uses "posthog" as an arbitrary MCP server name — leave; `packages/ui` "Sentry" icon name — leave) and in `script/`.

## Phase 2 — VS Code extension (`packages/kilo-vscode/`)

All paths Kilo-owned — no `kilocode_change` markers needed.

1. Delete `src/services/telemetry/` (telemetry-proxy.ts, types.ts, telemetry-proxy-utils.ts, webview-state.ts, errors.ts, index.ts).
2. `src/extension.ts`: drop the import (:25), `TelemetryProxy.getInstance()` (:63), `telemetry.configure`/`setEnabled` (:93-98), the `onDidChangeTelemetryEnabled` subscription (:116-120), `TelemetryProxy.capture(TITLE_BUTTON_CLICKED...)` (:479), and `shutdown()` (:756).
3. `src/services/cli-backend/server-manager.ts:157`: remove the `KILO_TELEMETRY_LEVEL` env line. **Keep** `KILO_MACHINE_ID` (still consumed by the machine-id helper via env override).
4. `src/KiloProvider.ts`: remove `TelemetryProxy`/`TelemetryPropertiesProvider`/`pushTelemetryState`/`watchTelemetryState` imports (:27-31), `implements ... TelemetryPropertiesProvider` (:347), `setProvider(this)` (:520), `getTelemetryProperties()` (:628-636), `telemetryStateDisposable` (:467, :731, :1081-1082, :5718), `case "telemetry"` handler (:1547-1548), and `chatAutocomplete?.telemetry.captureAcceptSuggestion` (:1475).
5. `src/MarketplacePanelProvider.ts`: remove `case "telemetry"` (:230-231) + imports (:18-19).
6. `src/agent-manager/fork-session.ts`: remove capture (:54) + import (:3).
7. `src/agent-manager/vscode-host.ts`: remove capture (:373) + import (:18); `src/agent-manager/host.ts:183` — drop the telemetry method from the host interface and all implementers (grep the interface method name).
8. Autocomplete telemetry: delete `src/services/autocomplete/classic-auto-complete/AutocompleteTelemetry.ts`; remove injections in `AutocompleteServiceManager.ts` (:8, :108) + the 3 `TelemetryProxy.capture` sites (:142-146, :268, :335) + `../telemetry` import (:4); `chat-autocomplete/ChatTextAreaAutocomplete.ts` (:4, :34, :39-41, all `this.telemetry.*` calls); `classic-auto-complete/AutocompleteInlineCompletionProvider.ts` (:35, :140, :157 + any `telemetry` method calls). Delete `classic-auto-complete/__tests__/AutocompleteTelemetry.test.ts`. In `__tests__/AutocompleteServiceManager.spec.ts` drop the `AutocompleteTelemetry` vi.mock (:92-94) and the stale `@roo-code/telemetry` vi.mock (:97-98) if the import no longer exists. If `classic-auto-complete/telemetry-utils.ts` becomes unused (it only served AutocompleteTelemetry), delete it plus `tests/unit/autocomplete-telemetry-utils.test.ts` — verify with knip.
9. Webview (`webview-ui/`):
   - Delete `agent-manager/telemetry.ts`; unwrap every `tracker(target)` usage in `agent-manager/` components (grep `tracker(`, `.click(`, `.track(`, `.use(`) — call the underlying action directly.
   - `src/types/messages/webview-messages.ts`: remove the `TelemetryRequest` type and the `telemetryState` message from the `ExtensionMessage`/`WebviewMessage` unions (verify exact names).
   - `src/context/feedback.tsx`: remove the `telemetryEnabled` signal + `telemetryState` listener + the `{ type: "telemetry", ... }` postMessage. Keep the rating UI local-only; `src/components/chat/TranscriptRow.tsx:117` (`enabled: feedback.telemetryEnabled()`) — adjust to always-enabled (or drop the flag) so feedback still renders.
   - `src/components/marketplace/MarketplaceView.tsx`: remove the `telemetry` helper + 4 call sites (:61, :83-84, :88, :92, :103).
   - `src/components/chat/KiloNotifications.tsx`: remove the `telemetry` postMessage (:83-84).
   - `src/context/work-style.tsx`: remove both `telemetry` postMessages (:78-79, :97-98).
   - `src/components/chat/SidebarTopBar.tsx`: remove the `telemetry` postMessage (:38-39) + `TelemetryEventName` import.
   - `src/components/settings/AboutKiloCodeTab.tsx`: remove the Telemetry section (:240-259).
10. Delete tests: `tests/unit/telemetry-errors.test.ts`, `tests/unit/telemetry-proxy-utils.test.ts`, `tests/unit/agent-manager-telemetry.test.ts`. Keep `tests/setup/vscode-mock.ts`.
11. `src/services/cli-backend/connection-service.ts:243` — fix the stale "Used by TelemetryProxy" comment (the `getServerConfig()` method itself stays; it's used by the SDK client setup).
12. `bun run knip` from `packages/kilo-vscode/` (CI enforces) — remove any newly-unused exports.

## Phase 3 — Build, verify, package

1. `packages/opencode/`: `bun run typecheck`, then `bun test` (full suite; at minimum the touched files above).
2. `packages/kilo-vscode/`: `bun run typecheck`, `bun run lint`, `bun run test:unit`, `bun run knip`.
3. Repo root: `bun run typecheck`, `bun run lint`. (Never run root `bun test`.)
4. Build the single-file CLI: from `packages/opencode/`, `bun run build --single --skip-install` → `dist/@kilocode/cli-windows-x64/bin/kilo.exe`.
5. Binary check (telemetry fully purged from the shipped CLI):
   `Select-String -Path "packages\opencode\dist\@kilocode\cli-windows-x64\bin\kilo.exe" -Pattern "us.i.posthog.com","phc_GK2Pxl","posthog-node"` — expect **0 matches**.
6. Package the extension: from `packages/kilo-vscode/`, `bun run package` (runs `prepare:cli-binary` → copies the binary to `bin/kilo.exe` + resources, `prepare:sdk`, typecheck, lint, production bundle), then:
   `bunx vsce package --no-dependencies --skip-license -o out/` → `out/kilo-code-7.6.2.vsix`.
   Note: `local-bin.ts` hashes CLI source inputs; the telemetry removal invalidates any cached binary, so `prepare:cli-binary` rebuilds automatically.
7. Install: `code --install-extension out/kilo-code-7.6.2.vsix --force` (or VS Code → Extensions → Install from VSIX).
8. Optional runtime proof: `bun run extension:isolated -- <some-workspace>` from `packages/kilo-vscode/`, run one session against the LM Studio provider, and confirm no outbound connection to `us.i.posthog.com`/`api.kilo.ai` (e.g. temporary hosts-file block or proxy log).

## Risks / notes

- **SDK regen output is generated code** — commit `packages/sdk/js/` after `./script/generate.ts`; do not hand-edit `src/gen/` or `src/v2/gen/`.
- **Shared upstream files** touched in Phase 1 (agent.ts, auth/index.ts, provider/auth.ts, session/llm/request.ts, server/routes/instance/httpapi/api.ts) lose telemetry-only kilocode_change blocks — this *reduces* merge surface vs upstream. Keep markers on the remaining kilo-provider blocks in request.ts.
- `setup.ts:cfg` — after removing the telemetry `enabled` flag, the `Config.getGlobal()` read may be unused; drop it (and the `app` AppRuntime read) only if nothing else in `bootstrap()` uses them.
- Windows single-file build needs the repo's normal CLI toolchain (bun; the build script may fetch a zig binary). `local-bin.ts` has a non-compiled fallback on failure, but a *compiled* binary is what ships in the .vsix.
- i18n strings `settings.aboutKiloCode.telemetry.*` in `packages/kilo-i18n` become unused after the About-tab section is removed — optional cleanup, not build-breaking.
- VS Code's *own* telemetry is the editor's, not this codebase's — if the user wants that off too, set `"telemetry.telemetryLevel": "off"` in VS Code settings (out of scope for the fork).

## Out of scope

- Kilo cloud features (gateway provider, cloud sessions, marketplace, profile/balance) — kept; only fire on explicit user action.
- `packages/kilo-docs/instrumentation-client.ts` (docs site only, not in the .vsix).
- `models.dev` model-catalog fetch (upstream functional behavior, cached locally).
