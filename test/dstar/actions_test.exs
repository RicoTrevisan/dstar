defmodule Dstar.ActionsTest do
  use ExUnit.Case, async: true

  alias Dstar.Actions

  # Define test modules so String.to_existing_atom works in decode_module
  defmodule MyApp.CounterView do
  end

  defmodule MyApp.Web.ChatView do
  end

  describe "encode_module/1" do
    test "encodes a simple module" do
      assert Actions.encode_module(MyApp.CounterView) ==
               "dstar-actions_test-my_app-counter_view"
    end
  end

  describe "decode_module/1" do
    test "decodes an encoded module" do
      encoded = Actions.encode_module(MyApp.CounterView)
      assert Actions.decode_module(encoded) == {:ok, MyApp.CounterView}
    end

    test "roundtrips nested modules" do
      encoded = Actions.encode_module(MyApp.Web.ChatView)
      assert Actions.decode_module(encoded) == {:ok, MyApp.Web.ChatView}
    end

    test "returns error for nonexistent module" do
      assert Actions.decode_module("does_not-exist") == :error
    end
  end

  describe "event/2 with module" do
    test "generates a post action with encoded module" do
      result = Actions.event(MyApp.CounterView, "increment")
      encoded = Actions.encode_module(MyApp.CounterView)
      assert result == "@post('/ds/#{encoded}/increment')"
    end
  end

  describe "event/1 dynamic" do
    test "generates a post action with dynamic module signal" do
      result = Actions.event("increment")
      assert result == "@post('/ds/' + $_dstar_module + '/increment')"
    end

    test "generates with custom module signal" do
      result = Actions.event("save", module: "my_module")
      assert result == "@post('/ds/my_module/save')"
    end
  end
end
