defmodule Dstar.Signals do
  @moduledoc """
  Functions for reading and patching Datastar signals via SSE.

      signals = Dstar.Signals.read(conn)
      conn |> patch(%{count: 42, message: "Hello"})
      conn |> patch(%{count: 42}, only_if_missing: true)
  """

  alias Dstar.SSE

  @datastar_key "datastar"
  @event_type "datastar-patch-signals"
  @default_only_if_missing false

  @doc """
  Reads signals from a Plug connection.

  For GET requests, reads from query parameters under the "datastar" key.
  For other methods, reads from the JSON request body.

  Returns a map of signals or an empty map if no signals are present.

  ## Example

      signals = Dstar.Signals.read(conn)
      # => %{"count" => 10, "message" => "Hello"}

  """
  @spec read(Plug.Conn.t()) :: map()
  def read(%Plug.Conn{method: "GET", query_params: params}) do
    case Map.get(params, @datastar_key) do
      nil -> %{}
      json_string -> decode_signals(json_string)
    end
  end

  def read(%Plug.Conn{} = conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        decode_signals(body)

      body_params when is_map(body_params) ->
        body_params

      _ ->
        %{}
    end
  end

  @doc """
  Patches signals on the client by sending an SSE event.

  ## Options

  - `:only_if_missing` - Only patch signals that don't exist on the client (default: false)
  - `:event_id` - Event ID for client tracking
  - `:retry` - Retry duration in milliseconds

  ## Example

      conn
      |> Dstar.Signals.patch(%{count: 42})
      |> Dstar.Signals.patch(%{message: "Hello"}, only_if_missing: true)

  """
  @spec patch(Plug.Conn.t(), map(), keyword()) :: Plug.Conn.t()
  def patch(conn, signals, opts \\ []) when is_map(signals) do
    json = Jason.encode!(signals)
    patch_raw(conn, json, opts)
  end

  @doc """
  Patches signals using a raw JSON string.

  ## Example

      conn
      |> Dstar.Signals.patch_raw(~s({"count": 42}))

  """
  @spec patch_raw(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  def patch_raw(conn, json, opts \\ []) when is_binary(json) do
    only_if_missing = Keyword.get(opts, :only_if_missing, @default_only_if_missing)

    data_lines =
      []
      |> maybe_add_only_if_missing(only_if_missing)
      |> add_signals_data(json)

    event_opts =
      [
        event_id: opts[:event_id],
        retry: opts[:retry]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    SSE.send_event!(conn, @event_type, data_lines, event_opts)
  end

  @doc """
  Formats a signals patch as an SSE event string (for stateless responses).

  ## Example

      format_patch(%{count: 42})
      # => "event: datastar-patch-signals\\ndata: signals {\\"count\\":42}\\n\\n"

  """
  @spec format_patch(map(), keyword()) :: String.t()
  def format_patch(signals, opts \\ []) when is_map(signals) do
    only_if_missing = Keyword.get(opts, :only_if_missing, @default_only_if_missing)
    json = Jason.encode!(signals)

    data_lines =
      []
      |> maybe_add_only_if_missing(only_if_missing)
      |> add_signals_data(json)

    SSE.format_event(@event_type, data_lines)
  end

  # Private helpers

  defp decode_signals(""), do: %{}
  defp decode_signals(nil), do: %{}

  defp decode_signals(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, map} -> map
      {:error, _} -> %{}
    end
  end

  defp maybe_add_only_if_missing(lines, false), do: lines

  defp maybe_add_only_if_missing(lines, true) do
    lines ++ ["onlyIfMissing true"]
  end

  defp add_signals_data(lines, json) do
    lines ++ ["signals " <> json]
  end
end
