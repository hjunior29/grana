defmodule GranaWeb.ChatHTMLTest do
  use ExUnit.Case, async: true

  alias GranaWeb.ChatHTML

  defp html(content), do: content |> ChatHTML.render() |> Phoenix.HTML.safe_to_string()

  test "keeps the allowed tags and drops everything else, content included" do
    assert html(~s|<p>Oi <strong>você</strong></p><script>alert(1)</script><h1>Título</h1>|) ==
             ~s|<p>Oi <strong>você</strong></p>alert(1)Título|
  end

  test "keeps only the agent's classes, translated to the app's ones" do
    assert html(~s|<span class="income foo" onclick="x()" style="color:red">+</span>|) ==
             ~s|<span class="ui-money-receita">+</span>|

    assert html(~s|<table><tr><td class="num expense">x</td></tr></table>|) =~
             ~s|<td class="ui-num ui-money-despesa">x</td>|

    assert html(~s|<p class="nope">x</p>|) == "<p>x</p>"
  end

  test "money values get the privacy span, inside any tag" do
    assert html("<p>Você gastou R$ 1.234,56 e recebeu R$ 10.</p>") ==
             ~s|<p>Você gastou <span class="ui-private whitespace-nowrap">R$ 1.234,56</span> e recebeu <span class="ui-private whitespace-nowrap">R$ 10</span>.</p>|

    assert html(~s|<table><tr><td class="num">-R$ 30,00</td></tr></table>|) =~
             ~s|<td class="ui-num"><span class="ui-private whitespace-nowrap">-R$ 30,00</span></td>|
  end

  test "plain-text answers saved before HTML become paragraphs" do
    assert html("Em março: R$ 30,00.\n\nMaiores:\n- Uber\n- <não é tag>") ==
             ~s|<p>Em março: <span class="ui-private whitespace-nowrap">R$ 30,00</span>.</p>| <>
               ~s|<p>Maiores:<br/>- Uber<br/>- &lt;não é tag&gt;</p>|
  end

  test "render_partial drops a tag still being typed" do
    assert html("<p>Gastos <stro") =~ "<p>Gastos "

    assert ChatHTML.render_partial("<p>Gastos <stro") |> Phoenix.HTML.safe_to_string() ==
             "<p>Gastos </p>"

    assert ChatHTML.render_partial("<ul><li>Uber") |> Phoenix.HTML.safe_to_string() ==
             "<ul><li>Uber</li></ul>"
  end

  test "known names get the privacy-name span, money inside the rest" do
    names = [~r/(?<![\p{L}\p{N}])(?:unimed bh)(?![\p{L}\p{N}])/iu]

    assert ChatHTML.render("<p>Unimed BH: R$ 450,00</p>", names) |> Phoenix.HTML.safe_to_string() ==
             ~s|<p><span class="ui-private-name">Unimed BH</span>: <span class="ui-private whitespace-nowrap">R$ 450,00</span></p>|
  end

  test "nil and empty content render nothing" do
    assert html(nil) == ""
    assert html("") == ""
  end
end
