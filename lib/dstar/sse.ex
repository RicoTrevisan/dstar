defmodule Dstar.SSE do
  @moduledoc """
  Server-Sent Event (SSE) connection and event formatting.

  This is the core of the library. It wraps a `Plug.Conn` in an `%SSE{}`
  struct and provides functions to send SSE events over it.

  ## Example

      conn
      |> Dstar.SSE.start()
      |> Dstar.SSE.send_event!("my-event", ["data line 1", "data line 2"])

  """

  @type t :: %__MODULE__{
          conn: Plug.Conn.t(),
          closed: boolean()
        }

  defstruct [:conn, closed: false]

  @doc """
  Starts an SSE connection from a Plug conn.

  Sets the content type to `text/event-stream`, disables caching,
  sends a chunked 200 response, and returns an `%SSE{}` struct.

  ## Example

      sse = Dstar.SSE.start(conn)

  """
  @spec start(Plug.Conn.t()) :: t()
  def start(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.send_chunked(200)
    |> new()
  end

  @doc """
  Creates an SSE struct from a conn that's already been set up for chunked streaming.

  Use `start/1` instead unless you need custom response headers.

  ## Example

      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)
      |> Dstar.SSE.new()

  """
  @spec new(Plug.Conn.t()) :: t()
  def new(conn) do
    %__MODULE__{conn: conn}
  end

  @doc """
  Sends an SSE event to the client.

  Returns `{:ok, sse}` on success, `{:error, reason}` on failure.

  ## Options

  - `:event_id` — Event ID for client tracking
  - `:retry` — Retry duration in milliseconds

  ## Example

      {:ok, sse} = Dstar.SSE.send_event(sse, "my-event", ["line1", "line2"])

  """
  @spec send_event(t(), String.t(), list(String.t()) | String.t(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def send_event(sse, event_type, data_lines, opts \\ [])

  def send_event(%__MODULE__{closed: true} = sse, _event_type, _data_lines, _opts) do
    {:error, {:closed, sse}}
  end

  def send_event(%__MODULE__{conn: conn} = sse, event_type, data_lines, opts) do
    data_lines = if is_binary(data_lines), do: [data_lines], else: data_lines

    event_content =
      []
      |> maybe_add_event(event_type)
      |> maybe_add_id(opts[:event_id])
      |> maybe_add_retry(opts[:retry])
      |> add_data_lines(data_lines)
      |> Enum.join()
      |> Kernel.<>("\n")

    case Plug.Conn.chunk(conn, event_content) do
      {:ok, conn} ->
        {:ok, %{sse | conn: conn}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends an SSE event, raising on error. Returns the updated `%SSE{}`.

  Useful for pipelines:

      sse
      |> send_event!("event-a", "data a")
      |> send_event!("event-b", "data b")

  """
  @spec send_event!(t(), String.t(), list(String.t()) | String.t(), keyword()) :: t()
  def send_event!(sse, event_type, data_lines, opts \\ []) do
    case send_event(sse, event_type, data_lines, opts) do
      {:ok, sse} -> sse
      {:error, reason} -> raise "Failed to send SSE event: #{inspect(reason)}"
    end
  end

  @doc """
  Formats a single SSE event as a string (no connection needed).

  Useful for building SSE response bodies without chunked streaming.

  ## Example

      Dstar.SSE.format_event("datastar-patch-signals", ["signals {\\"count\\":42}"])
      # => "event: datastar-patch-signals\\ndata: signals {\\"count\\":42}\\n\\n"

  """
  @spec format_event(String.t(), [String.t()]) :: String.t()
  def format_event(event_type, data_lines) do
    event_line = "event: #{event_type}\n"
    data_content = Enum.map_join(data_lines, "\n", &"data: #{&1}")
    "#{event_line}#{data_content}\n\n"
  end

  @doc "Returns true if the SSE connection has been marked closed."
  @spec closed?(t()) :: boolean()
  def closed?(%__MODULE__{closed: closed}), do: closed

  @doc "Marks the SSE connection as closed."
  @spec close(t()) :: t()
  def close(%__MODULE__{} = sse) do
    %{sse | closed: true}
  end

  # Private helpers

  defp maybe_add_event(lines, nil), do: lines
  defp maybe_add_event(lines, event_type), do: lines ++ ["event: #{event_type}\n"]

  defp maybe_add_id(lines, nil), do: lines
  defp maybe_add_id(lines, id), do: lines ++ ["id: #{id}\n"]

  defp maybe_add_retry(lines, nil), do: lines
  defp maybe_add_retry(lines, retry), do: lines ++ ["retry: #{retry}\n"]

  defp add_data_lines(lines, data_lines) do
    lines ++ Enum.map(data_lines, &"data: #{&1}\n")
  end
end
