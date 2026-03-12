defmodule Dstar do
  @moduledoc """
  Datastar SSE helpers for Elixir/Phoenix.

  A trivially small library: SSE connection management,
  signal patching, DOM element patching. That's it.

  ## Quick Example

      def increment(conn, _params) do
        signals = Dstar.read_signals(conn)
        count = signals["count"] || 0

        conn
        |> Dstar.start()
        |> Dstar.patch_signals(%{count: count + 1})
      end

  ## Modules

  - `Dstar.SSE` — Open SSE connections, send raw events
  - `Dstar.Signals` — Read signals from requests, patch signals on the client
  - `Dstar.Elements` — Patch and remove DOM elements
  - `Dstar.Actions` — Generate `@post(...)` expressions for Datastar attributes
  - `Dstar.Plugs.Dispatch` — Optional dynamic event dispatch plug
  """

  @doc """
  Starts an SSE connection on the given Plug conn.

  Sets content type to `text/event-stream`, disables caching,
  and initiates a chunked response. Returns a `%Dstar.SSE{}` struct.

  ## Example

      sse = Dstar.start(conn)

  """
  defdelegate start(conn), to: Dstar.SSE

  @doc """
  Reads Datastar signals from the request.

  For GET requests, reads from query params. For POST/PUT/etc, reads from the JSON body.

  ## Example

      signals = Dstar.read_signals(conn)
      count = signals["count"] || 0

  """
  defdelegate read_signals(conn), to: Dstar.Signals, as: :read

  @doc """
  Patches signals on the client via SSE.

  ## Example

      sse |> Dstar.patch_signals(%{count: 42})

  """
  def patch_signals(sse, signals, opts \\ []) do
    Dstar.Signals.patch(sse, signals, opts)
  end

  @doc """
  Patches a DOM element on the client via SSE.

  Requires a `:selector` option.

  ## Example

      sse |> Dstar.patch_elements("<span id=\\"count\\">42</span>", selector: "#count")

  """
  defdelegate patch_elements(sse, html, opts), to: Dstar.Elements, as: :patch

  @doc """
  Removes DOM elements on the client via SSE.

  ## Example

      sse |> Dstar.remove_elements("#old-item")

  """
  def remove_elements(sse, selector, opts \\ []) do
    Dstar.Elements.remove(sse, selector, opts)
  end

  @doc """
  Generates an event `@post(...)` expression for Datastar attributes.

  ## Examples

      Dstar.event(MyAppWeb.CounterHandler, "increment")
      # => "@post('/ds/my_app_web-counter_handler/increment')"

      Dstar.event("increment")
      # => "@post('/ds/' + $_dstar_module + '/increment')"

  """
  defdelegate event(module_or_name, name_or_opts), to: Dstar.Actions
end
