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

  describe "new/1 and closed?/1" do
    test "new SSE is not closed" do
      sse = SSE.new(%Plug.Conn{})
      refute SSE.closed?(sse)
    end

    test "close marks it closed" do
      sse = SSE.new(%Plug.Conn{}) |> SSE.close()
      assert SSE.closed?(sse)
    end
  end

  describe "send_event/4 when closed" do
    test "returns error" do
      sse = %SSE{conn: %Plug.Conn{}, closed: true}
      assert {:error, {:closed, _}} = SSE.send_event(sse, "test", ["data"])
    end
  end
end
