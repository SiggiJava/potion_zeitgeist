defmodule PotionZeitgeistWeb.StylesheetCheckTest do
  use PotionZeitgeistWeb.ConnCase, async: true

  alias PotionZeitgeistWeb.StylesheetCheck
  alias PotionZeitgeistWeb.StylesheetCheck.Scan

  describe "icons/0" do
    test "lists the heroicons the templates use, in every variant" do
      icons = StylesheetCheck.icons()

      # Admin > Projects, Invoices and Letter templates
      assert "hero-plus" in icons
      assert "hero-document-duplicate" in icons
      # an icon from the first version of the app
      assert "hero-user-plus" in icons
      # the 16px variant of the theme switch
      assert "hero-sun-micro" in icons

      assert icons == icons |> Enum.uniq() |> Enum.sort()
      assert Enum.all?(icons, &String.starts_with?(&1, "hero-"))
    end
  end

  describe "Scan.icons_in/2" do
    test "keeps quoted names of known icons only" do
      known = MapSet.new(["hero-plus", "hero-plus-circle", "hero-x-mark", "hero-sun-micro"])

      contents = [
        ~s(<.icon name="hero-plus" class="size-4" />),
        ~s(<.icon name="hero-plus-circle" /> "hero-sun-micro"),
        ~s(class="hero-x-mark size-4" "hero-unknown" "hero-" hero-x-mark),
        ~s(<.icon name="hero-plus" />)
      ]

      assert Scan.icons_in(contents, known) == ["hero-plus", "hero-plus-circle", "hero-sun-micro"]
    end
  end

  describe "Scan.known_icons/1" do
    @tag :tmp_dir
    test "names icons by folder like the Tailwind plugin", %{tmp_dir: dir} do
      for {folder, file} <- [
            {"24/outline", "plus.svg"},
            {"24/solid", "plus.svg"},
            {"20/solid", "plus.svg"},
            {"16/solid", "sun.svg"},
            {"16/solid", "README.txt"}
          ] do
        File.mkdir_p!(Path.join(dir, folder))
        File.write!(Path.join([dir, folder, file]), "<svg/>")
      end

      assert Scan.known_icons(dir) ==
               MapSet.new(["hero-plus", "hero-plus-solid", "hero-plus-mini", "hero-sun-micro"])
    end

    test "is empty when the heroicons folder is missing" do
      assert Scan.known_icons("/nonexistent/heroicons/optimized") == MapSet.new()
    end
  end

  describe "root layout" do
    test "carries the hidden notice with the icons to check", %{conn: conn} do
      html = conn |> get(~p"/setup") |> html_response(200)

      [notice] = Regex.run(~r/<div[^>]*id="stylesheet-outdated"[^>]*>/, html)
      assert notice =~ " hidden"
      [_, icons] = Regex.run(~r/data-icons="([^"]*)"/, notice)
      assert String.split(icons, " ") == StylesheetCheck.icons()

      assert html =~ "mix assets.build"
      assert html =~ "getComputedStyle(probe)"
    end
  end
end
