defmodule PotionZeitgeistWeb.StylesheetCheck.Scan do
  @moduledoc false
  # The compile-time scan behind PotionZeitgeistWeb.StylesheetCheck. It is a
  # module of its own because a module cannot call its own functions while it
  # is being compiled.

  # The suffixes and folders are the ones of assets/vendor/heroicons.js.
  @variants [
    {"", "24/outline"},
    {"-solid", "24/solid"},
    {"-mini", "20/solid"},
    {"-micro", "16/solid"}
  ]

  @doc """
  The .ex and .heex files under `dir`, the files that Tailwind scans for
  class names, sorted. The folders are walked one by one rather than with
  Path.wildcard/1, which would read brackets or braces in the checkout path
  as a pattern.
  """
  def sources(dir) do
    dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      path = Path.join(dir, name)

      cond do
        File.dir?(path) -> sources(path)
        Path.extname(name) in [".ex", ".heex"] -> [path]
        true -> []
      end
    end)
  end

  @doc """
  The names of all heroicons in `icons_dir`, with the class suffix of their
  variant, or an empty set when the folder is missing.
  """
  def known_icons(icons_dir) do
    for {suffix, dir} <- @variants,
        {:ok, files} <- [File.ls(Path.join(icons_dir, dir))],
        file <- files,
        Path.extname(file) == ".svg",
        into: MapSet.new() do
      "hero-" <> Path.basename(file, ".svg") <> suffix
    end
  end

  @doc """
  The icon names that occur as quoted strings in `contents` and are in
  `known`, sorted and without duplicates.
  """
  def icons_in(contents, known) do
    contents
    |> Enum.flat_map(&Regex.scan(quoted_icon(), &1, capture: :all_but_first))
    |> List.flatten()
    |> Enum.filter(&MapSet.member?(known, &1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A whole string literal such as "hero-plus" or "hero-sun-micro". Tailwind
  # scans this file too, so the pattern must not contain the icon prefix
  # followed by an opening bracket: Tailwind would take that for an icon
  # class with an arbitrary value, which the heroicons plugin cannot build.
  defp quoted_icon, do: ~r/"(hero(?:-[a-z0-9]+)+)"/
end

defmodule PotionZeitgeistWeb.StylesheetCheck do
  @moduledoc """
  Lets the browser find out whether the served app.css lacks icons the pages use.

  Tailwind builds app.css from the class names in the templates, and an icon
  such as `hero-plus` only exists in it when the build saw that name. When an
  update is pulled but the stylesheet is not rebuilt, or a browser keeps an
  old copy, new icons stay invisible while still taking up their room, so the
  text of an icon button looks pushed to the right, and new pages may miss
  other styles too.

  The root layout therefore carries a hidden notice and a small inline
  script. The script checks for every icon that the templates use whether
  app.css has a rule for it, and shows the notice with the update steps if
  one is missing. It needs neither app.css nor app.js, so it also works when
  both are outdated.

  `icons/0` lists those icons. It is worked out when this module is compiled:
  every quoted `"hero-…"` string in the files under lib/potion_zeitgeist_web
  that names an icon of the heroicons package in deps/heroicons/optimized,
  which are the files and icons the Tailwind build reads.
  """

  alias PotionZeitgeistWeb.StylesheetCheck.Scan

  # lib/potion_zeitgeist_web, the folder that assets/css/app.css names in @source
  @web_dir __DIR__
  @icons_dir Path.expand("../../deps/heroicons/optimized", __DIR__)

  @sources Scan.sources(@web_dir)

  for source <- @sources do
    @external_resource source
  end

  @known_icons Scan.known_icons(@icons_dir)

  if MapSet.size(@known_icons) == 0 do
    IO.warn(
      "no heroicons found in #{@icons_dir}, so the outdated stylesheet check is off. " <>
        "Run mix deps.get."
    )
  end

  @icons Scan.icons_in(Enum.map(@sources, &File.read!/1), @known_icons)

  # Changed files are covered by @external_resource. A template file that is
  # added or removed later is not, so Mix also asks this function whether the
  # module has to be compiled again.
  @doc false
  def __mix_recompile__? do
    Scan.sources(@web_dir) != @sources
  end

  @doc "The heroicons used in the templates, as their `hero-…` class names."
  def icons, do: @icons
end
