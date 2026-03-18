defmodule Dstar.ElementsTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias Dstar.{Elements, SSE}

  # Helper to create a chunked SSE conn
  defp chunked_conn do
    conn(:post, "/test")
    |> SSE.start()
  end

  describe "format_patch/2" do
    test "formats a basic element patch with selector" do
      result = Elements.format_patch("<span>42</span>", selector: "#count")

      assert result ==
               "event: datastar-patch-elements\n" <>
                 "data: selector #count\n" <>
                 "data: elements <span>42</span>\n\n"
    end

    test "formats element patch without selector (ID-based targeting)" do
      result = Elements.format_patch("<div id=\"feed\">New content</div>")

      assert result ==
               "event: datastar-patch-elements\n" <>
                 "data: elements <div id=\"feed\">New content</div>\n\n"

      refute result =~ "selector"
    end

    test "omits mode when default outer" do
      result = Elements.format_patch("<div>test</div>", selector: "#x")
      refute result =~ "mode"
    end

    test "formats with inner mode" do
      result = Elements.format_patch("<p>hello</p>", selector: ".box", mode: :inner)
      assert result =~ "mode inner"
      assert result =~ "selector .box"
    end

    test "formats with append mode" do
      result = Elements.format_patch("<li>item</li>", selector: "ul", mode: :append)
      assert result =~ "mode append"
    end

    test "formats with view transitions" do
      result =
        Elements.format_patch("<div>smooth</div>",
          selector: "#box",
          use_view_transitions: true
        )

      assert result =~ "useViewTransition true"
    end

    test "formats multiline HTML" do
      html = "<div>\n  <span>hello</span>\n</div>"
      result = Elements.format_patch(html, selector: "#target")
      assert result =~ "elements <div>"
      assert result =~ "elements   <span>hello</span>"
      assert result =~ "elements </div>"
    end

    test "does not raise when selector is omitted" do
      result = Elements.format_patch("<div id=\"x\">test</div>", [])
      assert result =~ "elements <div"
      refute result =~ "selector"
    end

    test "formats with svg namespace" do
      result =
        Elements.format_patch("<circle cx='50' cy='50' r='40'/>",
          selector: "#svg",
          namespace: :svg
        )

      assert result =~ "namespace svg"
    end

    test "formats with mathml namespace" do
      result =
        Elements.format_patch("<math><mi>x</mi></math>",
          selector: "#math",
          namespace: :mathml
        )

      assert result =~ "namespace mathml"
    end

    test "does not emit namespace line for default html namespace" do
      result =
        Elements.format_patch("<div>test</div>",
          selector: "#x",
          namespace: :html
        )

      refute result =~ "namespace"
    end

    test "does not emit namespace line when namespace not specified" do
      result = Elements.format_patch("<div>test</div>", selector: "#x")

      refute result =~ "namespace"
    end

    test "raises on invalid namespace" do
      assert_raise ArgumentError, ~r/Invalid namespace/, fn ->
        Elements.format_patch("<element/>", selector: "#x", namespace: :xml)
      end
    end

    test "raises when html is nil and mode is not :remove" do
      assert_raise ArgumentError, ~r/elements content is required/, fn ->
        Elements.format_patch(nil, selector: "#x", mode: :inner)
      end
    end

    test "allows nil html when mode is :remove" do
      result = Elements.format_patch(nil, selector: "#old", mode: :remove)
      assert result =~ "mode remove"
      assert result =~ "selector #old"
      refute result =~ "data: elements"
    end
  end

  describe "format_remove/2" do
    test "formats a basic element removal" do
      result = Elements.format_remove("#target")

      assert result ==
               "event: datastar-patch-elements\n" <>
                 "data: selector #target\n" <>
                 "data: mode remove\n\n"
    end

    test "formats removal with multiple selectors" do
      result = Elements.format_remove("#feed, #other")
      assert result =~ "mode remove"
      assert result =~ "selector #feed, #other"
      refute result =~ "data: elements"
    end
  end

  describe "remove/3" do
    test "sends mode remove and selector" do
      conn = chunked_conn()
      result = Elements.remove(conn, ".temporary")

      assert %Plug.Conn{state: :chunked} = result
    end

    test "passes through event_id and retry options" do
      conn = chunked_conn()
      result = Elements.remove(conn, "#old", event_id: "rm-1", retry: 2000)

      assert %Plug.Conn{state: :chunked} = result
    end
  end

  describe "patch/3" do
    test "patches without selector (ID-based)" do
      conn = chunked_conn()
      result = Elements.patch(conn, "<div id=\"feed\">content</div>")

      assert %Plug.Conn{state: :chunked} = result
    end

    test "patches with nil html and mode :remove" do
      conn = chunked_conn()
      result = Elements.patch(conn, nil, selector: "#old", mode: :remove)

      assert %Plug.Conn{state: :chunked} = result
    end

    test "raises with nil html and non-remove mode" do
      conn = chunked_conn()

      assert_raise ArgumentError, ~r/elements content is required/, fn ->
        Elements.patch(conn, nil, selector: "#x", mode: :outer)
      end
    end
  end
end
