defmodule GranaWeb.DemoComponents do
  @moduledoc """
  O que a demonstração pública (`Grana.Demo`) mostra ao visitante: a faixa fina no topo
  do app, com o funcionamento no modal do "Como funciona", o aviso no lugar de cada recurso
  desligado, com o motivo, e o recado das seções das Configurações que ficam só para ver.
  """

  use GranaWeb, :html

  alias Grana.Demo

  @doc "Faixa do topo do app na conta da demonstração, com o \"Como funciona\" num modal."
  def demo_banner(assigns) do
    ~H"""
    <div id="demo-banner" class="ui-demo-banner">
      <.icon name="hero-beaker" class="size-4 shrink-0" />
      <span>Demonstração com dados fictícios</span>
      <button
        id="demo-banner-more"
        type="button"
        class="ui-demo-banner-more"
        aria-haspopup="dialog"
        aria-controls="demo-info"
        phx-click={show_modal("demo-info")}
      >
        Como funciona <.icon name="hero-chevron-right-mini" class="size-4" />
      </button>
    </div>

    <div
      id="demo-info"
      class="modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="demo-info-title"
      phx-window-keydown={hide_modal("demo-info")}
      phx-key="Escape"
    >
      <div class="modal-box ui-demo-info">
        <button
          id="demo-info-close"
          type="button"
          class="ui-demo-info-close"
          aria-label="Fechar"
          phx-click={hide_modal("demo-info")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
        <span class="ui-demo-info-badge"><.icon name="hero-beaker" class="size-5" /></span>
        <h3 id="demo-info-title" class="ui-card-title">Como funciona a demonstração</h3>
        <p class="ui-help mt-1">
          Uma conta com um ano de movimento para você conhecer o Grana por dentro.
        </p>
        <ul class="ui-demo-info-list">
          <li :for={{icon, title, text} <- demo_facts()}>
            <span class="ui-demo-info-icon"><.icon name={icon} class="size-4" /></span>
            <div>
              <p class="font-medium">{title}</p>
              <p class="ui-help">{text}</p>
            </div>
          </li>
        </ul>
        <div class="modal-action">
          <.button type="button" variant="ghost" phx-click={hide_modal("demo-info")}>
            Entendi
          </.button>
          <.button href="/#instalacao" variant="primary">Instale o seu Grana</.button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click={hide_modal("demo-info")}></div>
    </div>
    """
  end

  defp demo_facts do
    [
      {"hero-users", "Conta compartilhada", "O que você muda, os outros visitantes também veem."},
      {"hero-arrow-path", "Volta ao original",
       "Os dados são refeitos quando o servidor reinicia, o que pode acontecer depois de um tempo sem visitas."},
      {"hero-key", "Sem chaves de verdade",
       "IA, email e Open Finance ficam desligados. A análise do Painel e a conversa do Chat já vêm escritas."},
      {"hero-hand-raised", "Nada pessoal aqui",
       "Não digite dados seus: quem entrar depois vê o mesmo que você."}
    ]
  end

  @doc "Aviso no lugar de um recurso desligado na demonstração (ver `Grana.Demo.reason/1`)."
  attr :feature, :atom, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def demo_notice(assigns) do
    assigns = assign(assigns, :reason, Demo.reason(assigns.feature))

    ~H"""
    <.notice id={@id || "demo-notice-#{@feature}"} class={@class} title="Desligado na demonstração">
      {@reason}
    </.notice>
    """
  end

  @doc """
  Recado de uma seção das Configurações na demonstração: os campos ficam à vista, mas
  desabilitados (`<fieldset disabled>`).
  """
  attr :id, :string, required: true

  def readonly_notice(assigns) do
    ~H"""
    <.notice id={@id} class="mb-4" title="Só para ver">
      Como esta é uma demonstração, os dados desta seção não podem ser alterados. Os campos
      ficam à vista para você conhecer como a configuração funciona.
    </.notice>
    """
  end
end
