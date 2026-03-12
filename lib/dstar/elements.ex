defmodule Dstar.Elements do
  @moduledoc """
  Functions for patching and removing DOM elements via SSE.

      sse |> patch("<div>New content</div>", selector: "#target")
      sse |> patch("<p>Inner</p>", selector: "#target", mode: :inner)
      sse |> remove("#target")
  """

  alias Dstar.SSE

  # Event type for element patches
  @event_type "datastar-patch-elements"

  # Default values
  @default_patch_mode :outer
  @default_use_view_transitions false

  # Valid patch modes
  @valid_modes ~w(outer inner remove replace prepend append before after)a

  @doc """
  Patches DOM elements with new HTML content.

  ## Options

  - `:selector` - CSS selector for target elements (required)
  - `:mode` - Patch mode (default: :outer)
  - `:use_view_transitions` - Enable View Transitions API (default: false)
  - `:event_id` - Event ID for client tracking
  - `:retry` - Retry duration in milliseconds

  ## Examples

      # Replace entire element
      sse |> patch("<div>Content</div>", selector: "#target")

      # Update inner HTML only
      sse |> patch("<p>New text</p>", selector: ".content", mode: :inner)

      # Append to element
      sse |> patch("<li>Item</li>", selector: "ul", mode: :append)

      # With view transitions
      sse |> patch("<div>Smooth</div>", selector: "#box", use_view_transitions: true)

  """
  @spec patch(SSE.t(), String.t(), keyword()) :: SSE.t()
  def patch(sse, html, opts \\ []) when is_binary(html) do
    selector = Keyword.fetch!(opts, :selector)
    mode = Keyword.get(opts, :mode, @default_patch_mode)
    use_view_transitions = Keyword.get(opts, :use_view_transitions, @default_use_view_transitions)

    unless mode in @valid_modes do
      raise ArgumentError, "Invalid patch mode: #{inspect(mode)}"
    end

    data_lines =
      []
      |> add_selector(selector)
      |> add_mode(mode)
      |> maybe_add_view_transitions(use_view_transitions)
      |> add_elements(html)

    event_opts =
      [
        event_id: opts[:event_id],
        retry: opts[:retry]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    SSE.send_event!(sse, @event_type, data_lines, event_opts)
  end

  @doc """
  Removes elements from the DOM by selector.

  ## Options

  - `:event_id` - Event ID for client tracking
  - `:retry` - Retry duration in milliseconds

  ## Example

      sse
      |> Dstar.Elements.remove(".temporary")
      |> Dstar.Elements.remove("#old-content")

  """
  @spec remove(SSE.t(), String.t(), keyword()) :: SSE.t()
  def remove(sse, selector, opts \\ []) when is_binary(selector) do
    data_lines = ["selector " <> selector]

    event_opts =
      [
        event_id: opts[:event_id],
        retry: opts[:retry]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    SSE.send_event!(sse, @event_type, data_lines, event_opts)
  end

  @doc """
  Formats an element patch as an SSE event string (for stateless responses).

  ## Example

      format_patch("<div>content</div>", selector: "#target", mode: :outer)

  """
  @spec format_patch(String.t(), keyword()) :: String.t()
  def format_patch(html, opts \\ []) when is_binary(html) do
    selector = Keyword.fetch!(opts, :selector)
    mode = Keyword.get(opts, :mode, @default_patch_mode)
    use_view_transitions = Keyword.get(opts, :use_view_transitions, @default_use_view_transitions)

    data_lines =
      []
      |> add_selector(selector)
      |> add_mode(mode)
      |> maybe_add_view_transitions(use_view_transitions)
      |> add_elements(html)

    SSE.format_event(@event_type, data_lines)
  end

  # Private helpers

  defp add_selector(lines, selector) do
    lines ++ ["selector " <> selector]
  end

  defp add_mode(lines, mode) do
    lines ++ ["mode " <> to_string(mode)]
  end

  defp maybe_add_view_transitions(lines, false), do: lines

  defp maybe_add_view_transitions(lines, true) do
    lines ++ ["useViewTransition true"]
  end

  defp add_elements(lines, html) do
    html_lines =
      html
      |> String.split("\n")
      |> Enum.map(&("elements " <> &1))

    lines ++ html_lines
  end
end
