defmodule Dstar.SignalsTest do
  use ExUnit.Case, async: true

  alias Dstar.Signals

  describe "read/1" do
    test "reads signals from GET query params" do
      conn = %Plug.Conn{
        method: "GET",
        query_params: %{"datastar" => ~s({"count":42})}
      }

      assert Signals.read(conn) == %{"count" => 42}
    end

    test "returns empty map when no datastar param on GET" do
      conn = %Plug.Conn{method: "GET", query_params: %{}}
      assert Signals.read(conn) == %{}
    end

    test "reads signals from POST body params" do
      conn = %Plug.Conn{
        method: "POST",
        body_params: %{"count" => 10, "name" => "test"}
      }

      assert Signals.read(conn) == %{"count" => 10, "name" => "test"}
    end

    test "returns empty map for empty body" do
      conn = %Plug.Conn{method: "POST", body_params: %{}}
      assert Signals.read(conn) == %{}
    end
  end

  describe "format_patch/2" do
    test "formats a basic signal patch" do
      result = Signals.format_patch(%{count: 42})

      assert result ==
               "event: datastar-patch-signals\ndata: signals {\"count\":42}\n\n"
    end

    test "formats with only_if_missing" do
      result = Signals.format_patch(%{count: 0}, only_if_missing: true)
      assert result =~ "onlyIfMissing true"
      assert result =~ "signals {\"count\":0}"
    end
  end
end
