# HEEx Rendering Patterns for Dstar

How to render HEEx templates and Phoenix components for use with Dstar's `patch_elements`.

`Dstar.patch_elements(conn, html, selector: "#target", mode: :inner)` sends HTML to the client via SSE to patch DOM elements. It accepts both raw strings and `Phoenix.HTML.safe()` tuples (the output of HEEx rendering).

---

## 1. Raw String Approach

Simplest for small fragments:

```elixir
conn
|> Dstar.start()
|> Dstar.patch_elements(
  ~s(<span id="count">#{count}</span>),
  selector: "#count"
)
```

**⚠️ Warning:** Raw strings are NOT HTML-escaped. Never interpolate user input directly.

---

## 2. Using ~H Sigil (Phoenix.Component)

For HEEx with proper escaping:

```elixir
import Phoenix.Component, only: [sigil_H: 2]

def handle_event(conn, "update", signals) do
  name = signals["name"]
  
  html = ~H"""
  <div id="greeting">
    <p>Hello, {@name}!</p>
  </div>
  """
  
  conn
  |> Dstar.start()
  |> Dstar.patch_elements(html, selector: "#greeting")
end
```

**Note:** `~H` returns a `Phoenix.HTML.safe()` tuple. Dstar accepts these directly — no conversion needed.

---

## 3. Rendering Existing Function Components

Call your existing Phoenix components:

```elixir
defmodule MyAppWeb.Components do
  use Phoenix.Component
  
  def todo_item(assigns) do
    ~H"""
    <li id={"todo-#{@todo.id}"} class="flex items-center gap-2">
      <input type="checkbox" 
             data-signals:done={"#{@todo.done}"}
             data-on:change={Dstar.post(TodoHandler, "toggle")} />
      <span data-class:line-through="$done">{@todo.text}</span>
    </li>
    """
  end
end
```

Render it in a handler — just call the function and pass the result directly. Dstar accepts `Phoenix.HTML.Safe` values, no conversion needed:

```elixir
def handle_event(conn, "add", signals) do
  todo = create_todo(signals)
  
  html = MyAppWeb.Components.todo_item(%{todo: todo})
  
  conn
  |> Dstar.start()
  |> Dstar.patch_elements(html, selector: "#todo-list", mode: :append)
end
```

---

## 4. Using Embedded HEEx Templates (.heex files)

Render a template file:

```elixir
# Assuming lib/my_app_web/controllers/todo_html/todo_item.html.heex exists
html = Phoenix.Template.render_to_string(
  MyAppWeb.TodoHTML,
  "todo_item",
  todo: todo
)
```

**Note:** This requires the view module to be compiled with the template.

---

## 5. Helper Module Pattern

Create a helper to reduce boilerplate:

```elixir
defmodule MyAppWeb.DstarHelpers do
  @doc "Render a component with assigns for patch_elements"
  def render_component(component, assigns) when is_function(component, 1) do
    component.(assigns)
  end
end
```

Usage:

```elixir
import MyAppWeb.DstarHelpers

html = render_component(&MyAppWeb.Components.todo_item/1, %{todo: todo})

conn
|> Dstar.start()
|> Dstar.patch_elements(html, selector: "#todos", mode: :append)
```

This is a thin wrapper — calling the component directly (as in section 3) works just as well. A helper like this is mainly useful if you want a consistent call convention or want to add logging/instrumentation later.

---

## 6. What `patch_elements` Accepts

Dstar's `patch_elements` accepts:

- **Binary strings** — raw, unescaped (use only for trusted content)
- **`{:safe, iodata}` tuples** — returned by `~H` sigil, function components, and anything implementing `Phoenix.HTML.Safe`

You never need to manually convert with `to_iodata()` or `IO.iodata_to_binary()` — just pass the component/sigil output directly as shown in sections 2, 3, and 5.

---

## 7. Layouts and Wrapping

For complex patches, you might render a wrapper:

```elixir
def handle_event(conn, "load_tab", signals) do
  tab = signals["active_tab"]
  
  html = case tab do
    "settings" -> settings_panel(%{user: user})
    "profile" -> profile_panel(%{user: user})
    _ -> dashboard(%{user: user})
  end
  
  conn
  |> Dstar.start()
  |> Dstar.patch_elements(html, selector: "#tab-content", mode: :inner)
end
```

---

## Best Practices

1. **Use `~H` sigil for inline templates** — gets you proper escaping and syntax highlighting
2. **Extract reusable components** — keep your handlers clean, render logic in components
3. **Never interpolate user input in raw strings** — always use `~H` or component rendering for user data
4. **Pass safe tuples directly** — Dstar handles them, no need to stringify
5. **Use helper modules** — reduce boilerplate for common rendering patterns
