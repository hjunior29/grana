defmodule GranaWeb.TermsLive do
  use GranaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Termos de Uso e Política de Privacidade")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <div class="rounded-lg border border-base-300 bg-base-200">
          <p class="text-sm font-medium text-primary mb-4">
            <.icon name="hero-shield-check" class="size-4" /> Transparência
          </p>
          <h1 class="text-3xl font-black tracking-normal sm:text-5xl">
            Termos de Uso e Política de Privacidade
          </h1>
          <p class="mt-3 text-sm opacity-50">Última atualização: 17 de fevereiro de 2026</p>
        </div>

        <div class="prose prose-sm max-w-none space-y-8 px-1 py-10 sm:px-2">
          <%!-- Termos de Uso --%>
          <section>
            <h2 class="text-xl font-bold mb-4">1. Termos de Uso</h2>

            <h3 class="text-lg font-semibold mt-6 mb-2">1.1. Aceitação dos Termos</h3>
            <p>
              Ao acessar e utilizar a plataforma Grana, você concorda com os presentes
              Termos de Uso. Caso não concorde com qualquer disposição, não utilize a plataforma.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">1.2. Descrição do Serviço</h3>
            <p>
              O Grana é uma plataforma de gestão financeira pessoal que permite ao usuário:
            </p>
            <ul class="list-disc list-inside space-y-1 ml-4">
              <li>Fazer upload de extratos bancários em formato CSV e PDF</li>
              <li>Categorizar transações de forma automática e manual</li>
              <li>Visualizar dashboards e gráficos sobre suas finanças</li>
              <li>Obter análises financeiras utilizando inteligência artificial</li>
            </ul>

            <h3 class="text-lg font-semibold mt-6 mb-2">1.3. Modelo BYOK (Bring Your Own Key)</h3>
            <p>
              As funcionalidades de inteligência artificial do Grana utilizam o modelo BYOK (Bring Your Own Key). O usuário é responsável por fornecer sua própria chave de API do Google Gemini nas configurações
              da plataforma. As requisições de IA são realizadas diretamente entre o navegador do usuário e os
              servidores do Google, utilizando a chave fornecida pelo próprio usuário. O Grana não se responsabiliza por custos associados ao uso da API Key do usuário junto ao
              provedor de IA, nem por eventuais limitações de uso impostas pelo provedor.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">1.4. Cadastro e Conta</h3>
            <p>
              Para utilizar a plataforma, o usuário deve criar uma conta fornecendo um endereço de e-mail válido.
              O usuário é responsável por manter a segurança de suas credenciais de acesso e por todas as
              atividades realizadas em sua conta.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">1.5. Uso Adequado</h3>
            <p>O usuário compromete-se a:</p>
            <ul class="list-disc list-inside space-y-1 ml-4">
              <li>Utilizar a plataforma apenas para fins pessoais e lícitos</li>
              <li>Não tentar acessar dados de outros usuários</li>
              <li>Não utilizar a plataforma para atividades fraudulentas</li>
              <li>Não realizar engenharia reversa ou tentativas de exploração de vulnerabilidades</li>
            </ul>

            <h3 class="text-lg font-semibold mt-6 mb-2">1.6. Disponibilidade</h3>
            <p>
              O Grana é oferecido "como está" (as is), sem garantias de disponibilidade ininterrupta.
              O serviço pode ser descontinuado ou modificado a qualquer momento, sem aviso prévio.
              O Grana não se responsabiliza por perdas decorrentes de indisponibilidade da plataforma.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">1.7. Gratuidade</h3>
            <p>
              A utilização do Grana é gratuita. Não há cobrança de assinatura, taxas ou valores pelo
              uso da plataforma. O usuário arca apenas com eventuais custos de sua API Key junto ao
              provedor de IA, caso exceda os limites do plano gratuito.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">1.8. Limitação de Responsabilidade</h3>
            <p>
              O Grana é uma ferramenta auxiliar de organização financeira e não constitui assessoria
              financeira, contábil ou tributária. As análises geradas por IA são meramente informativas.
              O usuário é o único responsável por suas decisões financeiras.
            </p>
          </section>

          <%!-- Política de Privacidade --%>
          <section>
            <h2 class="text-xl font-bold mb-4">2. Política de Privacidade</h2>
            <p>
              Esta Política de Privacidade descreve como o Grana coleta, utiliza e protege seus dados
              pessoais, em conformidade com a Lei Geral de Proteção de Dados Pessoais (Lei nº 13.709/2018 — LGPD).
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">2.1. Dados Coletados</h3>
            <p>O Grana coleta e armazena os seguintes dados:</p>
            <ul class="list-disc list-inside space-y-1 ml-4">
              <li>
                <strong>Dados de cadastro:</strong> endereço de e-mail e senha (hash criptográfico)
              </li>
              <li>
                <strong>Dados financeiros:</strong>
                transações extraídas dos extratos bancários enviados pelo usuário (descrição, valor, data, banco)
              </li>
              <li>
                <strong>Dados de configuração:</strong>
                preferências do usuário, categorias personalizadas e chave de API criptografada
              </li>
              <li>
                <strong>Dados de uso:</strong>
                análises geradas, filtros aplicados e histórico de categorizações
              </li>
            </ul>

            <h3 class="text-lg font-semibold mt-6 mb-2">2.2. Finalidade do Tratamento</h3>
            <p>Os dados são tratados exclusivamente para:</p>
            <ul class="list-disc list-inside space-y-1 ml-4">
              <li>Prover as funcionalidades da plataforma (categorização, dashboards, análises)</li>
              <li>Manter o histórico financeiro do usuário entre sessões</li>
              <li>Aplicar regras de categorização aprendidas pelo sistema</li>
              <li>Autenticação e segurança da conta</li>
            </ul>

            <h3 class="text-lg font-semibold mt-6 mb-2">2.3. Base Legal (LGPD)</h3>
            <p>
              O tratamento dos dados pessoais é realizado com base no
              <strong>consentimento do titular</strong>
              (Art. 7º, I, da LGPD), manifestado no momento do cadastro e aceite destes termos, e na
              <strong>execução de contrato</strong>
              (Art. 7º, V, da LGPD), necessária para a prestação
              do serviço solicitado pelo próprio usuário.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">2.4. Compartilhamento de Dados</h3>
            <p>
              O Grana <strong>não compartilha, vende ou transfere</strong>
              dados pessoais ou financeiros
              do usuário com terceiros, exceto:
            </p>
            <ul class="list-disc list-inside space-y-1 ml-4">
              <li>
                <strong>Google Gemini:</strong> quando o usuário utiliza funcionalidades de IA,
                dados financeiros resumidos são enviados diretamente ao Google utilizando a API Key
                do próprio usuário. O Grana não intermedia nem armazena essas comunicações.
              </li>
              <li>
                <strong>Obrigação legal:</strong> quando exigido por ordem judicial ou determinação
                de autoridade competente.
              </li>
            </ul>

            <h3 class="text-lg font-semibold mt-6 mb-2">2.5. Armazenamento e Segurança</h3>
            <p>Os dados são protegidos por:</p>
            <ul class="list-disc list-inside space-y-1 ml-4">
              <li>Criptografia de senhas com algoritmo bcrypt</li>
              <li>Comunicação exclusivamente via HTTPS</li>
              <li>API Keys armazenadas de forma criptografada no banco de dados</li>
              <li>Sessões autenticadas com tokens seguros</li>
            </ul>

            <h3 class="text-lg font-semibold mt-6 mb-2">2.6. Direitos do Titular (LGPD Art. 18)</h3>
            <p>O usuário tem direito a:</p>
            <ul class="list-disc list-inside space-y-1 ml-4">
              <li>
                <strong>Acesso:</strong> consultar todos os dados pessoais armazenados na plataforma
              </li>
              <li>
                <strong>Correção:</strong>
                alterar seus dados pessoais (email, senha) nas configurações
              </li>
              <li>
                <strong>Eliminação:</strong>
                excluir completamente sua conta e todos os dados associados a qualquer momento, através das configurações da plataforma
              </li>
              <li>
                <strong>Revogação do consentimento:</strong>
                deixar de utilizar a plataforma e excluir sua conta
              </li>
              <li><strong>Portabilidade:</strong> exportar suas transações em formato CSV</li>
            </ul>
            <p>
              Para exercer qualquer direito, o usuário pode acessar as configurações da sua conta ou
              entrar em contato através dos canais disponíveis.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">2.7. Retenção de Dados</h3>
            <p>
              Os dados pessoais são mantidos enquanto a conta do usuário estiver ativa. Ao excluir a conta,
              todos os dados são removidos permanentemente do banco de dados, incluindo transações,
              categorias, análises e configurações. Esta exclusão é irreversível.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">2.8. Cookies</h3>
            <p>
              O Grana utiliza cookies estritamente necessários para o funcionamento da autenticação
              e manutenção da sessão do usuário. Não são utilizados cookies de rastreamento,
              analytics ou publicidade.
            </p>
          </section>

          <%!-- Disposições Gerais --%>
          <section>
            <h2 class="text-xl font-bold mb-4">3. Disposições Gerais</h2>

            <h3 class="text-lg font-semibold mt-6 mb-2">3.1. Alterações</h3>
            <p>
              O Grana reserva-se o direito de alterar estes Termos e esta Política de Privacidade a
              qualquer momento. As alterações serão publicadas nesta página com a data de atualização.
              O uso continuado da plataforma após as alterações constitui aceite dos novos termos.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">3.2. Legislação Aplicável</h3>
            <p>
              Estes Termos são regidos pelas leis da República Federativa do Brasil, em especial o
              Marco Civil da Internet (Lei nº 12.965/2014), a Lei Geral de Proteção de Dados Pessoais
              (Lei nº 13.709/2018) e o Código de Defesa do Consumidor (Lei nº 8.078/1990), quando aplicável.
            </p>

            <h3 class="text-lg font-semibold mt-6 mb-2">3.3. Foro</h3>
            <p>
              Fica eleito o foro da comarca do domicílio do usuário para dirimir quaisquer controvérsias
              decorrentes destes Termos, conforme previsto no Código de Defesa do Consumidor.
            </p>
          </section>
        </div>

        <div class="mt-12 pt-8 border-t border-base-content/10 text-center">
          <.link
            navigate={if @current_scope, do: ~p"/dashboard", else: ~p"/users/register"}
            class="btn btn-primary"
          >
            Li os Termos de Uso e Política de Privacidade
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
