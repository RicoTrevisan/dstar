defmodule Dstar.Plugs.RenameCsrfParam do
  @moduledoc """
  Renames a CSRF body param to `_csrf_token` so that `Plug.CSRFProtection`
  can find it.

  ## Why this exists

  Dstar's verb helpers (`Dstar.post/2,3`, etc.) do **not** read CSRF from a
  Datastar signal. They read the token from Phoenix's standard
  `<meta name="csrf-token">` tag and send it as an `x-csrf-token` header.
  That avoids any interaction between normal Datastar signal round-trips and
  the CSRF header used by SSE routes.

  However, regular Phoenix form POSTs (e.g. sign-in, settings) still go
  through `Plug.CSRFProtection`, which looks for the token in
  `conn.body_params["_csrf_token"]`.

  If you want a Datastar-driven form request to satisfy that plug, you can
  expose the token as a **non-prefixed** signal (default `csrf`). Because it
  is not `_`-prefixed, Datastar will include it in each request body. This
  plug then copies that param into `_csrf_token` in `body_params` before
  `Plug.CSRFProtection` runs.

  ## Usage

      # In your Phoenix router (before :protect_from_forgery):
      plug Dstar.Plugs.RenameCsrfParam

      # With a custom source param name:
      plug Dstar.Plugs.RenameCsrfParam, from: "my_token"

  ## Options

  - `:from` — Source param name to copy from. Default: `"csrf"`.
  """

  @behaviour Plug

  @impl Plug
  def init(opts) do
    %{from: Keyword.get(opts, :from, "csrf")}
  end

  @impl Plug
  def call(conn, %{from: from}) do
    case conn.params do
      %{"_csrf_token" => _} ->
        conn

      %{^from => token} ->
        %{conn | body_params: Map.put(conn.body_params, "_csrf_token", token)}

      _ ->
        conn
    end
  end
end
