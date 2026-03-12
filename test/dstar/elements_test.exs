defmodule Dstar.ElementsTest do
  use ExUnit.Case, async: true

  alias Dstar.Elements

  describe "format_patch/2" do
    test "formats a basic element patch" do
      result = Elements.format_patch("<span>42</span>", selector: "#count")

      assert result ==
               "event: datastar-patch-elements\n" <>
                 "data: selector #count\n" <>
                 "data: mode outer\n" <>
                 "data: elements <span>42</span>\n\n"
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

    test "raises on missing selector" do
      assert_raise KeyError, fn ->
        Elements.format_patch("<div>test</div>", [])
      end
    end

    test "uses default outer mode when not specified" do
      result = Elements.format_patch("<div>test</div>", selector: "#x")
      assert result =~ "mode outer"
    end
  end
end
