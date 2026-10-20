defmodule GranaWeb.QuickActionComponents do
  use GranaWeb, :html

  def palette(assigns) do
    assigns = assign(assigns, :groups, groups())

    ~H"""
    <div id="quick-actions" phx-hook="QuickActions" phx-update="ignore" class="flex shrink-0">
      <button
        id="quick-actions-open"
        type="button"
        class="quick-actions-trigger"
        aria-label="Abrir busca rápida"
        aria-haspopup="dialog"
        aria-controls="quick-actions-dialog"
        aria-keyshortcuts="Meta+k Control+k"
      >
        <.icon name="hero-magnifying-glass" class="size-4" />
        <span class="hidden lg:inline">Buscar</span>
        <kbd class="quick-actions-shortcut hidden lg:inline-flex" aria-hidden="true">
          <span data-shortcut="mac">⌘ K</span>
          <span data-shortcut="other">Ctrl K</span>
        </kbd>
      </button>

      <dialog
        id="quick-actions-dialog"
        class="quick-actions-dialog"
        aria-labelledby="quick-actions-title"
        aria-describedby="quick-actions-description"
      >
        <div class="quick-actions-heading">
          <div>
            <h2 id="quick-actions-title" class="ui-section-title">Busca rápida</h2>
            <p id="quick-actions-description" class="ui-help mt-1 hidden sm:block">
              Encontre uma tela, ação ou busca salva, ou ative o modo privacidade.
            </p>
          </div>
          <button
            id="quick-actions-close"
            type="button"
            class="quick-actions-close"
            aria-label="Fechar busca rápida"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="quick-actions-search">
          <.icon name="hero-magnifying-glass" class="size-5 shrink-0 ui-text-secondary" />
          <.input
            id="quick-actions-query"
            name="quick_actions_query"
            type="search"
            value=""
            class="quick-actions-input"
            placeholder="O que você quer fazer?"
            aria-label="Buscar ações, telas e buscas salvas"
            role="combobox"
            aria-autocomplete="list"
            aria-expanded="false"
            aria-controls="quick-actions-results"
            autocomplete="off"
          />
        </div>

        <div class="quick-actions-scroll">
          <div id="quick-actions-results" role="listbox" aria-label="Resultados da busca rápida">
            <%= for {title, actions} <- @groups do %>
              <section
                data-quick-group
                role="group"
                aria-label={title}
              >
                <h3 class="quick-actions-group-title ui-caption" aria-hidden="true">{title}</h3>
                <.link
                  :for={{id, label, icon, path, keywords, suggested} <- actions}
                  id={"quick-action-#{id}"}
                  navigate={path}
                  class="quick-actions-option"
                  role="option"
                  tabindex="-1"
                  aria-selected="false"
                  data-quick-action
                  data-keywords={keywords}
                  data-suggested={to_string(suggested)}
                >
                  <.icon name={icon} class="size-4 shrink-0" />
                  <span class="min-w-0 flex-1 truncate" data-quick-label>{label}</span>
                  <.icon name="hero-arrow-up-right" class="size-3.5 shrink-0 ui-text-tertiary" />
                </.link>
              </section>
              <section
                :if={title == "Ações"}
                id="quick-actions-privacy"
                data-quick-group
                role="group"
                aria-label="Privacidade"
              >
                <h3 class="quick-actions-group-title ui-caption" aria-hidden="true">Privacidade</h3>
                <button
                  :for={{kind, label, icon, keywords, suggested} <- privacy_actions()}
                  id={"quick-action-privacy-#{kind}"}
                  type="button"
                  class="quick-actions-option"
                  role="option"
                  tabindex="-1"
                  aria-selected="false"
                  data-quick-action
                  data-privacy={kind}
                  data-keywords={keywords}
                  data-suggested={to_string(suggested)}
                >
                  <.icon name={icon} class="size-4 shrink-0" />
                  <span class="min-w-0 flex-1 truncate" data-quick-label>{label}</span>
                </button>
              </section>
            <% end %>
            <section
              id="quick-actions-saved"
              data-quick-group
              role="group"
              aria-label="Buscas salvas"
              hidden
            >
              <h3 class="quick-actions-group-title ui-caption" aria-hidden="true">Buscas salvas</h3>
            </section>
          </div>
          <div id="quick-actions-empty" class="quick-actions-empty" hidden>
            <.icon name="hero-magnifying-glass" class="size-6 ui-text-secondary" />
            <p class="ui-body font-medium">Nenhum resultado encontrado</p>
            <p class="ui-help">Tente palavras como meta, senha, extrato ou modelo.</p>
          </div>
          <p id="quick-actions-status" class="ui-help px-4 pb-3" role="status" aria-live="polite"></p>
        </div>

        <div class="quick-actions-footer ui-help">
          <span class="hidden sm:inline"><kbd>↑</kbd> <kbd>↓</kbd> para escolher</span>
          <span><kbd>Enter</kbd> para abrir</span>
          <span><kbd>Esc</kbd> para fechar</span>
        </div>

        <template id="quick-actions-saved-template">
          <.link
            navigate={~p"/transactions"}
            class="quick-actions-option"
            role="option"
            tabindex="-1"
            aria-selected="false"
            data-quick-action
            data-suggested="true"
          >
            <.icon name="hero-bookmark" class="size-4 shrink-0" />
            <span class="ui-private-name min-w-0 flex-1 truncate" data-quick-label></span>
            <.icon name="hero-arrow-up-right" class="size-3.5 shrink-0 ui-text-tertiary" />
          </.link>
        </template>
      </dialog>
    </div>
    """
  end

  # Labels for the state before opening; the hook rewrites them ("Ocultar" or "Mostrar")
  # from the classes of the app shell each time the palette opens.
  defp privacy_actions do
    [
      {"all", "Alternar modo privacidade (valores e nomes)", "hero-eye-slash",
       "privacidade ocultar mostrar esconder valores nomes gravar tela olho", true},
      {"values", "Alternar ocultar valores", "hero-banknotes",
       "privacidade ocultar mostrar esconder valores reais dinheiro", false},
      {"names", "Alternar ocultar nomes", "hero-user",
       "privacidade ocultar mostrar esconder nomes descrições pessoas lojas", false}
    ]
  end

  defp groups do
    [
      {"Ações",
       [
         {"import", "Importar extrato ou fatura", "hero-cloud-arrow-up", ~p"/upload",
          "arquivo csv pdf banco nubank bradesco enviar upload", true},
         {"new-goal", "Criar meta", "hero-plus", ~p"/goals?action=new",
          "nova objetivo limite orçamento gastos receita investimento", true},
         {"new-category", "Criar categoria", "hero-plus", ~p"/categories?action=new",
          "nova classificação organizar", true},
         {"new-chat", "Iniciar conversa", "hero-chat-bubble-left-right", ~p"/chat/new",
          "novo chat perguntar assistente ia", true}
       ]},
      {"Páginas",
       [
         {"dashboard", "Ir para Painel", "hero-chart-bar", ~p"/dashboard",
          "resumo início dashboard análise saldo gráficos", true},
         {"transactions", "Ver transações", "hero-list-bullet", ~p"/transactions",
          "lançamentos movimentos despesas receitas lista gastos", true},
         {"goals", "Ir para Metas", "hero-flag", ~p"/goals",
          "objetivos limites orçamento gastos receita investimento", false},
         {"categories", "Ir para Categorias", "hero-tag", ~p"/categories",
          "classificação organizar", false},
         {"chat", "Abrir Chat", "hero-chat-bubble-left-right", ~p"/chat",
          "conversas perguntar assistente ia", false},
         {"fixed", "Ver despesas fixas", "hero-arrow-path", ~p"/dashboard?tab=recurring",
          "recorrência recorrentes assinaturas variáveis mensal", false},
         {"search", "Abrir pesquisa avançada", "hero-magnifying-glass",
          ~p"/transactions?mode=advanced", "buscar filtrar filtros consulta buscas salvas",
          false},
         {"history", "Ver histórico de importações", "hero-clock", ~p"/upload?tab=historico",
          "arquivos extratos faturas enviados uploads", false},
         {"calendar", "Ver calendário de importações", "hero-calendar-days",
          ~p"/upload?tab=calendario", "cobertura histórico meses arquivos extratos faturas",
          false}
       ]},
      {"Configurações",
       [
         {"settings", "Abrir Configurações", "hero-cog-6-tooth", ~p"/users/settings",
          "ajustes opções", false},
         {"account", "Gerenciar conta e senha", "hero-user-circle",
          ~p"/users/settings?section=account", "email acesso identidade nome cpf segurança",
          false},
         {"preferences", "Mudar aparência e privacidade", "hero-paint-brush",
          ~p"/users/settings?section=preferences",
          "tema estilo claro escuro ocultar valores nomes", false},
         {"ai", "Configurar inteligência artificial", "hero-cpu-chip",
          ~p"/users/settings?section=ai",
          "ia modelo modelos provedor gemini openai claude anthropic ollama chave api", false},
         {"integrations", "Configurar Open Finance e email", "hero-puzzle-piece",
          ~p"/users/settings?section=integrations",
          "integrações banco pluggy conectar smtp email", false},
         {"backup", "Gerenciar backup", "hero-archive-box", ~p"/users/settings?section=backup",
          "cópia segurança restaurar baixar dados", false},
         {"system", "Ver estado do sistema", "hero-server-stack",
          ~p"/users/settings?section=system", "diagnóstico versão integrações servidor", false}
       ]}
    ]
  end
end
