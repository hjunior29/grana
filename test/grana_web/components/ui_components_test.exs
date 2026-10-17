defmodule GranaWeb.UiComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  import GranaWeb.CoreComponents, only: [button: 1]
  import GranaWeb.UiComponents

  alias Phoenix.LiveView.JS

  defp html(rendered), do: rendered |> rendered_to_string() |> LazyHTML.from_fragment()
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp text(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()

  test "card alinha a descrição ao título e marca o tom de perigo" do
    assigns = %{}

    doc =
      html(~H"""
      <.card id="c1" icon="hero-user" title="Conta" description="Texto">conteúdo</.card>
      <.card id="c2" tone={:danger} icon="hero-trash" title="Perigo">x</.card>
      """)

    assert text(doc, "#c1 h3") == "Conta"
    assert count(doc, "#c1 header p.ml-8") == 1
    assert count(doc, "#c2.border-error\\/30") == 1
    assert count(doc, "#c2 header p") == 0
  end

  test "section mostra a divisória só quando pedida" do
    assigns = %{}

    doc =
      html(~H"""
      <.section id="s1" title="A">a</.section>
      <.section id="s2" title="B" divider>b</.section>
      """)

    assert count(doc, "#s1.border-t") == 0
    assert count(doc, "#s2.border-t") == 1
  end

  test "tag usa o vocabulário fixo e aceita texto próprio" do
    assigns = %{}

    doc =
      html(~H"""
      <.tag id="t1" kind="env" />
      <.tag id="t2" kind="ativo">2FA ativo</.tag>
      """)

    assert text(doc, "#t1.ui-tag-env") == ".env"
    assert text(doc, "#t2.ui-tag-ativo") == "2FA ativo"
  end

  test "notice traz um ícone fixo por tom e role de alerta no erro" do
    assigns = %{}

    doc =
      html(~H"""
      <.notice id="n1" tone={:warning}>a</.notice>
      <.notice id="n2" tone={:error}>b</.notice>
      """)

    assert count(doc, "#n1.ui-notice-warning .hero-exclamation-triangle") == 1
    assert count(doc, "#n2[role=alert] .hero-exclamation-circle") == 1
  end

  test "item_row renderiza título, subtítulo, tags e ações" do
    assigns = %{}

    doc =
      html(~H"""
      <ul>
        <.item_row id="r1" title="Banco" subtitle="Conta">
          <:tags><.tag kind="salvo" /></:tags>
          <:actions><button id="act">Ok</button></:actions>
        </.item_row>
      </ul>
      """)

    assert text(doc, "#r1 .font-medium") == "Banco"
    assert count(doc, "#r1 .ui-tag-salvo") == 1
    assert count(doc, "#r1 #act") == 1
  end

  test "env_field mostra só o nome da variável, somente leitura, com a tag" do
    assigns = %{}

    doc = html(~H|<.env_field id="e1" label="Servidor" var="SMTP_HOST" />|)

    assert count(doc, "input#e1[readonly][value=SMTP_HOST]") == 1
    assert count(doc, "label .ui-tag-env") == 1
  end

  test "empty_state mostra a ação quando há" do
    assigns = %{}

    doc =
      html(~H"""
      <.empty_state id="v1" icon="hero-inbox" title="Vazio" text="Nada aqui">
        <:action><button id="go">Criar</button></:action>
      </.empty_state>
      """)

    assert text(doc, "#v1 p.font-medium") == "Vazio"
    assert count(doc, "#v1 #go") == 1
  end

  test "confirm_modal sem form confirma por JS; com form envia por evento" do
    assigns = %{form: Phoenix.Component.to_form(%{"a" => ""}, as: :f)}

    doc =
      html(~H"""
      <.confirm_modal
        id="m1"
        title="Remover?"
        confirm="Remover"
        loading="Removendo…"
        on_confirm={JS.push("remover")}
      >
        texto
      </.confirm_modal>
      <.confirm_modal
        id="m2"
        open
        title="Apagar"
        confirm="Apagar"
        loading="Apagando…"
        form={@form}
        on_confirm="apagar"
        on_cancel={JS.push("cancelar")}
      >
        texto
      </.confirm_modal>
      """)

    assert count(doc, "#m1.modal-open") == 0
    assert count(doc, "#m1 button#m1-confirm[phx-click*=remover]") == 1
    assert count(doc, "#m1 form") == 0
    assert count(doc, "#m2.modal-open") == 1
    assert count(doc, "#m2 form#m2-form[phx-submit=apagar] button#m2-confirm") == 1
  end

  test "button: variantes, tamanho, ícone e texto de carregamento" do
    assigns = %{}

    doc =
      html(~H"""
      <.button id="b1" variant="primary" size="sm" icon="hero-plus" loading="Salvando…">
        Salvar
      </.button>
      <.button id="b2" variant="danger">Apagar</.button>
      <.button id="b3" class="btn btn-sm">Legado</.button>
      <.button id="b4" variant="secondary" href="/x">Link</.button>
      """)

    assert count(doc, "button#b1.btn.btn-primary.btn-sm .hero-plus") == 1
    assert doc |> LazyHTML.query("#b1") |> LazyHTML.text() =~ "Salvando…"
    assert count(doc, "button#b2.btn-error.btn-soft") == 1
    assert count(doc, "button#b3.btn.btn-sm") == 1
    assert count(doc, "a#b4.btn") == 1
  end

  test "page_header mostra título, subtítulo e ações" do
    assigns = %{}

    doc =
      html(~H"""
      <.page_header title="Metas" subtitle="Acompanhe">
        <:actions><button id="nova">Nova meta</button></:actions>
      </.page_header>
      """)

    assert text(doc, "h1.ui-page-title") == "Metas"
    assert count(doc, "#nova") == 1
  end

  test "auth_card centraliza título, conteúdo e rodapé" do
    assigns = %{}

    doc =
      html(~H"""
      <.auth_card id="a1" title="Entrar" subtitle="Bem-vindo">
        <input id="campo" />
        <:footer>link</:footer>
      </.auth_card>
      """)

    assert text(doc, "#a1 h1") == "Entrar"
    assert count(doc, "#a1 #campo") == 1
    assert text(doc, "#a1 > div:last-child") == "link"
  end

  test "tabs: patch vira link, evento vira botão, contador vira tag" do
    assigns = %{}

    doc =
      html(~H"""
      <.tabs id="t">
        <:tab id="t-a" label="Resumo" icon="hero-banknotes" active event="switch_tab" value="banking" />
        <:tab id="t-b" label="Histórico" count={3} patch="/upload?tab=historico" />
      </.tabs>
      """)

    assert count(doc, "button#t-a.tab-active[phx-click=switch_tab][phx-value-tab=banking]") == 1
    assert count(doc, "a#t-b[data-phx-link=patch] .ui-tag-neutro") == 1
  end

  test "filter_bar, chip_group e chip marcam o ativo" do
    assigns = %{}

    doc =
      html(~H"""
      <.filter_bar id="f">
        <.chip_group label="Banco">
          <.chip id="c1" active phx-click="select_bank" phx-value-bank="all">Todos</.chip>
          <.chip id="c2" phx-click="select_bank" phx-value-bank="nubank">Nubank</.chip>
        </.chip_group>
      </.filter_bar>
      """)

    assert count(doc, "#f [role=group][aria-label=Banco]") == 1
    assert count(doc, "button#c1.ui-chip-active[aria-pressed=true][phx-value-bank=all]") == 1
    assert count(doc, "button#c2[aria-pressed=false]") == 1
    assert count(doc, "button#c2.ui-chip-active") == 0
  end

  test "money formata em reais e colore pelo sentido" do
    assigns = %{pos: Decimal.new("1234.5"), neg: Decimal.new("-10")}

    doc =
      html(~H"""
      <.money id="m1" value={@pos} tone={:auto} sign />
      <.money id="m2" value={@neg} tone={:auto} />
      <.money id="m3" value={nil} />
      <.money id="m4" value={@pos} tone={:investimento} />
      """)

    assert text(doc, "#m1.ui-money-receita") == "+R$ 1.234,50"
    assert text(doc, "#m2.ui-money-despesa") == "-R$ 10,00"
    assert text(doc, "#m3") == "—"
    assert count(doc, "#m4.ui-money-investimento") == 1
    assert count(doc, ".ui-private") == 4
  end

  test "private_text marca só os valores em reais do texto" do
    assigns = %{}

    doc =
      html(~H"""
      <p id="t1">
        <.private_text text="Gastou R$ 1.234,56 em mercado, -R$ 10 no Uber e +R$ 5,00 de volta." />
      </p>
      <p id="t2"><.private_text text="Fatura de USD 12,00 em 3 parcelas, 45% do limite." /></p>
      <p id="t3"><.private_text text={nil} /></p>
      """)

    assert doc |> LazyHTML.query("#t1 .ui-private") |> Enum.map(&LazyHTML.text/1) ==
             ["R$ 1.234,56", "-R$ 10", "+R$ 5,00"]

    assert text(doc, "#t1") ==
             "Gastou R$ 1.234,56 em mercado, -R$ 10 no Uber e +R$ 5,00 de volta."

    assert text(doc, "#t2 .ui-private") == "USD 12,00"
    assert text(doc, "#t2") =~ "45% do limite"
    assert count(doc, "#t3 span") == 0
  end

  test "switch é um botão com o estado em aria-checked" do
    assigns = %{}

    doc =
      html(~H"""
      <.switch id="on" label="Ligado" checked phx-click="toggle" />
      <.switch id="off" label="Desligado" checked={false} />
      """)

    assert count(doc, ~s|button#on.ui-switch-on[role="switch"][aria-checked="true"]|) == 1
    assert count(doc, ~s|#on[phx-click="toggle"][aria-label="Ligado"]|) == 1
    assert count(doc, ~s|#off[aria-checked="false"]|) == 1
    assert count(doc, "#off.ui-switch-on") == 0
  end

  test "stat_tile aceita tom e legenda" do
    assigns = %{}

    doc =
      html(
        ~H|<.stat_tile id="s" label="Receitas" value="R$ 1,00" tone={:receita} caption="no mês" />|
      )

    assert count(doc, "#s-value.ui-money-receita") == 1
    assert text(doc, "#s-value .ui-private") == "R$ 1,00"
    assert doc |> LazyHTML.text() =~ "no mês"
  end

  test "notice aceita ação à direita" do
    assigns = %{}

    doc =
      html(~H"""
      <.notice id="n" tone={:warning}>
        395 sem categoria
        <:action><a id="cat" href="/categories">Categorizar</a></:action>
      </.notice>
      """)

    assert count(doc, "#n #cat") == 1
  end

  test "source_chip mostra banco, tipo e o símbolo do Open Finance" do
    assigns = %{}

    doc =
      html(~H"""
      <.source_chip id="o1" bank="nubank" type="fatura" />
      <.source_chip id="o2" bank="bradesco" type="extrato" open_finance />
      """)

    assert text(doc, "#o1") =~ "Nubank"
    assert text(doc, "#o1") =~ "(Fatura)"
    assert count(doc, "#o1 svg") == 0
    assert count(doc, "#o2 svg") == 1
  end

  test "form_modal envia o form e cancela por JS" do
    assigns = %{form: Phoenix.Component.to_form(%{"name" => ""}, as: :goal)}

    doc =
      html(~H"""
      <.form_modal
        id="gm"
        title="Nova meta"
        form={@form}
        on_submit="save"
        on_cancel={JS.push("cancel")}
        submit="Criar meta"
      >
        <input id="name" />
      </.form_modal>
      """)

    assert count(doc, "#gm.modal-open form#gm-form[phx-submit=save] #name") == 1
    assert text(doc, "#gm-submit") =~ "Criar meta"
  end

  test "ai_required_modal explica o motivo e leva às Configurações" do
    assigns = %{}

    doc = html(~H|<.ai_required_modal reason="Ler PDFs usa IA." />|)

    assert doc |> LazyHTML.text() =~ "Ler PDFs usa IA."
    assert count(doc, "a[href='/users/settings?section=ai']") == 1
  end

  test "format_pct usa vírgula e limita acima de 999%" do
    assert GranaWeb.UiComponents.format_pct(0.0) == "0,0%"
    assert GranaWeb.UiComponents.format_pct(34.04) == "34,0%"
    assert GranaWeb.UiComponents.format_pct(989_494.0) == ">999%"
  end

  test "count_label pluraliza e separa milhares" do
    assert GranaWeb.UiComponents.count_label(1, "regra", "regras") == "1 regra"
    assert GranaWeb.UiComponents.count_label(0, "regra", "regras") == "0 regras"

    assert GranaWeb.UiComponents.count_label(1671, "transação", "transações") ==
             "1.671 transações"
  end
end
