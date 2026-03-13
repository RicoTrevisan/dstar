defmodule Dstar.SSETest do
  use ExUnit.Case, async: true

  alias Dstar.SSE

  describe "format_event/2" do
    test "formats a basic event" do
      result = SSE.format_event("my-event", ["hello world"])
      assert result == "event: my-event\ndata: hello world\n\n"
    end

    test "formats multiple data lines" do
      result = SSE.format_event("my-event", ["line1", "line2", "line3"])

      assert result ==
               "event: my-event\ndata: line1\ndata: line2\ndata: line3\n\n"
    end

    test "formats empty data lines" do
      result = SSE.format_event("my-event", [])
      assert result == "event: my-event\n\n\n"
    end
  end
end
