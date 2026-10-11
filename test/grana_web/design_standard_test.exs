defmodule GranaWeb.DesignStandardTest do
  use ExUnit.Case, async: true

  # Telas já migradas ao padrão de `doc/DESIGN.md`. Ao migrar uma tela, acrescente o
  # arquivo aqui.
  @migrated [
    "lib/grana_web/live/user_live/settings.ex",
    "lib/grana_web/components/account_components.ex",
    "lib/grana_web/components/ai_components.ex",
    "lib/grana_web/components/backup_components.ex",
    "lib/grana_web/components/ui_components.ex",
    "lib/grana_web/live/user_live/login.ex",
    "lib/grana_web/live/user_live/two_factor.ex",
    "lib/grana_web/live/user_live/forgot_password.ex",
    "lib/grana_web/live/user_live/reset_password.ex",
    "lib/grana_web/live/setup_live.ex",
    "lib/grana_web/live/onboarding_live.ex",
    "lib/grana_web/live/categories_live.ex",
    "lib/grana_web/live/goals_live.ex",
    "lib/grana_web/live/transactions_live.ex",
    "lib/grana_web/live/upload_live.ex",
    "lib/grana_web/components/open_finance_components.ex",
    "lib/grana_web/components/filter_components.ex",
    "lib/grana_web/live/dashboard_live.ex",
    "lib/grana_web/live/analysis_live.ex",
    "lib/grana_web/components/layouts.ex",
    "lib/grana_web/components/core_components.ex"
  ]

  defp forbidden do
    [
      {~r/(?<![\w\/-])opacity-(?!0\b|100\b)\d/,
       "opacidade em texto: use ui-text-secondary ou ui-text-tertiary (opacity-0 e opacity-100 são só de animação)"},
      {~r/rounded-(lg|xl)\b/, "raio solto: use ui-rounded-box ou ui-rounded-field"},
      {~r/data-confirm/, "confirmação nativa: use <.confirm_modal>"},
      {~r/\bbadge\b/, "badge solto: use <.tag>"},
      {~r/text-\[\d+px\]/, "tamanho solto: use ui-help ou ui-caption"}
    ]
  end

  for entry <- @migrated do
    {file, stop} = if is_tuple(entry), do: entry, else: {entry, nil}

    test "#{file} não usa classes proibidas pelo padrão de design" do
      source = File.read!(unquote(file))

      source =
        case unquote(stop) do
          nil -> source
          marker -> source |> String.split(marker) |> hd()
        end

      violations =
        for {pattern, reason} <- forbidden(), match = Regex.run(pattern, source) do
          "#{hd(match)}: #{reason}"
        end

      assert violations == []
    end
  end
end
