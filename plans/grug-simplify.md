# Grug-Brain Simplification Plan for `dstar`

## Grug Summary

grug look at codebase. grug see 1,742 lines across 15 files. grug see GenServer-per-session, Registry, Token auth, Socket struct with event queues, a custom page renderer, a custom streaming plug. grug recognize pattern: **grug accidentally built LiveView**.

mentor say: "SSE Plug, few helpers, PubSub, done." mentor right. datastar whole point is **client holds state**. server stateless. no need process-per-session.

grug plan: **delete 10 files, keep 5, end up ~350 lines total**. library becomes bag of functions. no processes. no supervision tree. no callbacks. no macros. just functions that format SSE events and write them to a `conn`.

---

## What Was Built vs What Was Asked

| What was asked | What was built |
|---|---|
| SSE Plug | `Dstar.SSE` ✅ |
| A few event helpers | `Dstar.Signals`, `Dstar.Elements` ✅ |
| PubSub for real-time | Full GenServer-per-session system with Registry, Token auth, Socket struct, subscriber monitoring, enter_loop, keepalive... 🔴 |
| One dispatch route | `Dstar.Plugs.Dispatch` ✅ (but also Plugs.Page and Plugs.Stream) |
| Sit on top of deadview Phoenix | Zero Phoenix deps, custom Plug.Router, own page rendering, own session handling 🔴 |

---

## 🔴 The Axe List — What to CUT

### 1. `lib/dstar/server.ex` (284 lines) — THE biggest overbuilt piece

A GenServer-per-session that holds state, receives events, monitors subscribers, sends updates via messages, has an `enter_loop` with keepalive. This is LiveView's channel process. Datastar doesn't need it. The whole point of Datastar is that the **client holds the state** (signals). The server is stateless — receive an event with the current signals, process it, send back SSE patches. Done.

For real-time (chat, ticker), no process per session needed. Just:
- An SSE connection (the `conn` itself, held open)
- A PubSub subscription
- When PubSub fires → write to the SSE conn

That's 20 lines in the consuming app's controller, not a GenServer state machine in the library.

### 2. `lib/dstar/registry.ex` (28 lines) — Only exists to support Server

Registry via-tuples for GenServer lookup. No Server → no Registry.

### 3. `lib/dstar/token.ex` (48 lines) — Only exists to authenticate Server sessions

Without per-session GenServers, there's no session to authenticate back to. Phoenix already has session handling (plugs, cookies, CSRF).

### 4. `lib/dstar/socket.ex` (315 lines) — Rebuilt `Phoenix.LiveView.Socket`

`assigns`, `signals`, `events` queue, `patch_elements`, `execute_script`, `redirect`, `console_log`… This is a mini LiveView socket. With plain controllers, no need to accumulate state in a struct and flush it later. Just:
- Read signals from the request
- Do logic
- Write SSE events directly to the conn

### 5. `lib/dstar/plugs/page.ex` (147 lines) — Phoenix already renders pages

With deadview Phoenix there are controllers, templates, layouts. No need for a custom Plug that generates `<!DOCTYPE html>` and injects a `<script>` tag. That's what the Phoenix layout does.

### 6. `lib/dstar/plugs/stream.ex` (80 lines) — Only exists for the GenServer model

The token-verify → subscribe-to-GenServer → enter_loop flow. Without Server, this whole file goes away. For real-time SSE, the consuming app writes a controller action that opens a chunked response and subscribes to PubSub.

### 7. `lib/dstar/application.ex` (15 lines) — Only starts the Registry

Without Registry, no OTP application needed. The library becomes a pure set of functions with no processes. Remove `mod: {Dstar.Application, []}` from `mix.exs` too.

### 8. `lib/dstar.ex` behaviour + `__using__` macro (130 lines) — Rebuilt `use Phoenix.LiveView`

The `mount/3`, `handle_event/3`, `handle_info/2`, `render/1` callback system is LiveView's API almost 1:1. With controllers, a "view" is just a controller action. No behaviour, no macro, no socket struct. Just functions.

### 9. `lib/dstar/scripts.ex` (106 lines) — Over-abstracted

Appending a `<script>` to `<body>` via element patch is a cute trick, but for a "trivially small" library it's one abstraction too many. If someone needs it, it's 3 lines with `Elements.patch/3` (mode: :append, selector: "body").

### 10. `lib/dstar/helpers/js.ex` (13 lines) — Only used by Socket.redirect and Socket.console_log

Those are Socket methods. No Socket → no need for this.

---

## ✅ What to KEEP (the "trivially small" core)

### 1. `lib/dstar/sse.ex` (~100 lines) — Keep, simplify slightly

**This IS the library.** Opens SSE connection, sends events, formats events. The `%Dstar.SSE{}` struct wrapping `conn` is good — it's the pipeline token.

**Changes:**
- Keep as-is. It's clean. The struct, `new/1`, `send_event!/4`, `format_event/2`, `close/1` are all good.
- Consider adding a convenience `start/1` that does the `put_resp_content_type` + `send_chunked` + `new` dance, since every user will do it:

```elixir
def start(conn) do
  conn
  |> Plug.Conn.put_resp_content_type("text/event-stream")
  |> Plug.Conn.put_resp_header("cache-control", "no-cache")
  |> Plug.Conn.send_chunked(200)
  |> new()
end
```

### 2. `lib/dstar/signals.ex` (~145 lines) — Keep as-is

Clean module. `read/1` parses signals from the conn. `patch/3` sends signal updates via SSE. `format_patch/2` for non-streaming. All good. No changes needed.

### 3. `lib/dstar/elements.ex` (~152 lines) — Keep as-is

Clean module. `patch/3` sends DOM patches via SSE. `remove/3` removes elements. `format_patch/2` for non-streaming. All good. No changes needed.

### 4. `lib/dstar/actions.ex` (~100 lines) — Keep, simplify

`event/1,2` helper for generating `@post(...)` expressions in templates. `encode_module/1` and `decode_module/1` for URL-safe module names. Keep all three — they're the glue for the dispatch route.

**Changes:**
- Remove the `$_dstar_module` signal default from `event/1`. With Phoenix controllers, the module is known at compile time:
  ```elixir
  # Before: event("increment") => "@post('/ds/' + $_dstar_module + '/increment')"
  # After:  event(MyApp.CounterController, "increment") => "@post('/ds/my_app-counter_controller/increment')"
  ```
- Actually... keep both forms. The dynamic `$_dstar_module` signal pattern is still useful if someone stores the module in signals. But make the explicit module form the primary API.

### 5. `lib/dstar/plugs/dispatch.ex` (~135 lines) — Keep, gut heavily

The mentor's exact suggestion: `post "/ds/:module/:event", DatastarController, :dispatch`. Currently 135 lines with live/stateless branching, Socket creation, mount-then-handle_event double-init, SSE response building.

**Simplify to ~40 lines:**
- Decode module from URL
- Verify it's an allowed module (allowlist, not "does it implement Dstar behaviour")
- Read signals from request body
- Call `module.handle_event(event, signals, conn)` — the module returns an `%SSE{}` or a `conn`
- Done

But actually... **should Dispatch even be in the library?** It's a one-liner in a Phoenix controller:

```elixir
# In the consuming app
defmodule MyAppWeb.DatastarController do
  use MyAppWeb, :controller

  @modules %{
    "counter" => MyAppWeb.CounterController,
    "todo" => MyAppWeb.TodoController,
  }

  def dispatch(conn, %{"module" => mod, "event" => event}) do
    module = Map.fetch!(@modules, mod)
    signals = Dstar.Signals.read(conn)
    module.handle_event(conn, event, signals)
  end
end
```

**Decision:** Keep it in the library as a convenience, but make it dead simple. No Socket, no mount, no live/stateless split. Just decode → allowlist check → call handler.

---

## `lib/dstar.ex` — What it becomes

No behaviour. No macro. Just a thin convenience module that re-exports the most common functions so users can write `Dstar.start(conn)` instead of `Dstar.SSE.start(conn)`.

```elixir
defmodule Dstar do
  @moduledoc """
  Datastar SSE helpers for Elixir/Phoenix.

  A trivially small library: SSE connection management,
  signal patching, DOM element patching. That's it.
  """

  defdelegate start(conn), to: Dstar.SSE
  defdelegate read_signals(conn), to: Dstar.Signals, as: :read
  defdelegate patch_signals(sse, signals, opts \\ []), to: Dstar.Signals, as: :patch
  defdelegate patch_elements(sse, html, opts), to: Dstar.Elements, as: :patch
  defdelegate remove_elements(sse, selector, opts \\ []), to: Dstar.Elements, as: :remove
  defdelegate event(name, opts \\ []), to: Dstar.Actions
end
```

~15 lines. Done.

---

## Target File Structure

```
dstar/
├── mix.exs                    # deps: plug, jason (that's it)
├── lib/
│   ├── dstar.ex               # Thin convenience delegations (~15 lines)
│   └── dstar/
│       ├── sse.ex             # SSE struct, start, send_event, format (~110 lines)
│       ├── signals.ex         # read from conn, patch to client (~145 lines)
│       ├── elements.ex        # patch/remove DOM elements (~152 lines)
│       └── actions.ex         # event() helper, encode/decode module (~100 lines)
```

**5 files. ~520 lines. No processes. No supervision tree. No behaviours. No macros.**

(Some of those lines are docs/typespecs — actual logic is ~200 lines.)

---

## How Usage Looks After

### Counter (stateless — the 90% case)

```elixir
# router.ex
post "/ds/counter/:event", CounterController, :dispatch

# counter_controller.ex
defmodule MyAppWeb.CounterController do
  use MyAppWeb, :controller

  def show(conn, _params) do
    render(conn, :counter, count: 0)  # normal Phoenix template
  end

  def dispatch(conn, %{"event" => "increment"}) do
    signals = Dstar.read_signals(conn)
    count = signals["count"] || 0

    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{count: count + 1})
    # returns %SSE{conn: conn} — Phoenix doesn't need conn back for chunked
  end
end
```

No mount. No socket. No behaviour. **Just read signals, do math, send patch.** A junior dev reads this and understands it in 30 seconds.

### Real-time Ticker (the 10% case)

```elixir
# In the Phoenix app, NOT in the library:
defmodule MyAppWeb.TickerController do
  use MyAppWeb, :controller

  def stream(conn, _params) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, "ticker")

    sse = Dstar.start(conn)
    sse_loop(sse)
  end

  defp sse_loop(sse) do
    receive do
      {:tick, count} ->
        sse = Dstar.patch_elements(sse, "<span id=\"count\">#{count}</span>", selector: "#count")
        sse_loop(sse)

      :stop ->
        :ok
    after
      30_000 ->
        # keepalive
        case Plug.Conn.chunk(sse.conn, ": keepalive\n\n") do
          {:ok, conn} -> sse_loop(%{sse | conn: conn})
          {:error, _} -> :ok
        end
    end
  end
end
```

PubSub is the real-time primitive. The library doesn't need to own it. The consuming app writes 20 lines.

### Using the Dispatch Plug (optional convenience)

```elixir
# router.ex
post "/ds/:module/:event", Dstar.Plugs.Dispatch, modules: [
  MyAppWeb.CounterHandler,
  MyAppWeb.TodoHandler,
]

# counter_handler.ex — just a module with a function, not a GenServer
defmodule MyAppWeb.CounterHandler do
  def handle_event(conn, "increment", signals) do
    count = signals["count"] || 0

    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{count: count + 1})
  end
end
```

---

## Implementation Steps

### Phase 1: Delete (10 minutes)

1. Delete these files:
   - `lib/dstar/server.ex`
   - `lib/dstar/registry.ex`
   - `lib/dstar/token.ex`
   - `lib/dstar/socket.ex`
   - `lib/dstar/scripts.ex`
   - `lib/dstar/plugs/page.ex`
   - `lib/dstar/plugs/stream.ex`
   - `lib/dstar/application.ex`
   - `lib/dstar/helpers/js.ex`

2. Remove from `mix.exs`:
   - `mod: {Dstar.Application, []}` from `application/0`
   - `plug_cowboy` dep (only needed if library was serving)

### Phase 2: Simplify Kept Files (20 minutes)

3. **`lib/dstar.ex`** — Gut entirely. Replace with thin delegation module (~15 lines).

4. **`lib/dstar/sse.ex`** — Add `start/1` convenience function. Rest stays.

5. **`lib/dstar/signals.ex`** — No changes needed. Already clean.

6. **`lib/dstar/elements.ex`** — No changes needed. Already clean.

7. **`lib/dstar/actions.ex`** — Minor: add explicit module form of `event/2` as primary API. Keep dynamic `$_dstar_module` form as fallback.

8. **`lib/dstar/plugs/dispatch.ex`** — Rewrite from 135 lines to ~40:
   - Accept `modules:` option (allowlist)
   - Decode module from URL param
   - Check against allowlist
   - Read signals
   - Call `module.handle_event(conn, event, signals)`
   - No Socket, no mount, no live/stateless branching

### Phase 3: Tests (15 minutes)

9. Write simple tests:
   - `test/dstar/sse_test.exs` — format_event produces correct SSE text
   - `test/dstar/signals_test.exs` — read parses signals, format_patch produces correct SSE
   - `test/dstar/elements_test.exs` — format_patch produces correct SSE
   - `test/dstar/actions_test.exs` — encode/decode module roundtrips, event/1 produces correct string

### Phase 4: Docs (10 minutes)

10. Update `README.md` with the Phoenix controller examples above. Show:
    - Stateless counter (the 90% case)
    - Real-time ticker (the 10% case, in consuming app)
    - Dispatch plug (optional convenience)

---

## What About Scripts?

grug think about it. `Dstar.Scripts.execute/3` is just:

```elixir
Elements.patch(sse, "<script>#{js}</script>", selector: "body", mode: :append)
```

One line. Not worth a module. If users need it, show it in docs as a recipe. Same for redirect (it's `window.location = url`) and console_log.

---

## Risk Check

| Risk | Mitigation |
|---|---|
| "But what about real-time?" | PubSub + receive loop in controller. 20 lines. Library doesn't need to own it. |
| "But what about session state?" | Datastar's whole point: client holds state via signals. Server is stateless. |
| "But the dispatch plug needs to know allowed modules" | Allowlist option. Explicit > magic. |
| "What if someone already uses the current API?" | This is v0.1.0, pre-release. No users. Clean break. |
| "Won't the streaming controller block a Phoenix process?" | Yes, same as any long-poll. Phoenix handles this fine with enough acceptors. For scale, use Bandit (which is default now). |

---

## The Mentor Test

> "Strip it all out and the library becomes trivially small: an SSE Plug, a few helpers to generate Datastar events, PubSub for the real time, done."

After this plan:
- ✅ SSE Plug → `Dstar.SSE`
- ✅ Few helpers → `Dstar.Signals`, `Dstar.Elements`, `Dstar.Actions`
- ✅ PubSub → Not in the library. In the consuming app. As it should be.
- ✅ Trivially small → 5 files, ~520 lines (including docs), ~200 lines of actual logic
- ✅ Deadview Phoenix → Library has zero opinions about rendering. Use Phoenix controllers and templates.

**grug happy. grug go swing axe now.**
