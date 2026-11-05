#!/usr/bin/env bash
# Instala (ou atualiza) o Grana como serviço systemd.
#
#   ./deploy/install.sh --version v1.1.0     # baixa o tarball pronto do GitHub Releases
#   ./deploy/install.sh                      # idem, usando a última versão
#   ./deploy/install.sh --from-source        # compila neste servidor (Erlang/OTP 28 + Elixir 1.18)
#   ./deploy/install.sh --update [...]       # atualiza uma instalação existente e reinicia
#
# Idempotente: pode ser rodado de novo. Não mexe em /etc/grana/grana.env nem nos
# dados em /var/lib/grana se já existirem.
set -euo pipefail

REPO="hjunior29/grana"
APP_DIR="/opt/grana"
ENV_DIR="/etc/grana"
ENV_FILE="$ENV_DIR/grana.env"
DATA_DIR="/var/lib/grana"
UNIT_FILE="/etc/systemd/system/grana.service"

MODE="download"
VERSION=""

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from-source) MODE="source" ;;
    --version) VERSION="${2:-}"; [ -n "$VERSION" ] || die "--version precisa de um valor (ex.: v1.1.0)"; shift ;;
    --update) ;; # mesmo caminho da instalação: refaz o download/build e reinicia
    -h|--help) usage 0 ;;
    *) warn "Opção desconhecida: $1"; usage 1 ;;
  esac
  shift
done

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

command -v systemctl >/dev/null || die "systemd é necessário (systemctl não encontrado)."
[ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null || die "Rode como root ou instale o sudo."

case "$(uname -m)" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) die "Arquitetura não suportada: $(uname -m)" ;;
esac

install_system_deps() {
  # pdftotext (poppler-utils) lê os extratos em PDF.
  if command -v pdftotext >/dev/null; then return; fi
  log "Instalando poppler-utils (pdftotext)"
  if command -v apt-get >/dev/null; then
    as_root apt-get update -qq && as_root apt-get install -y -qq poppler-utils ca-certificates curl
  elif command -v dnf >/dev/null; then
    as_root dnf install -y -q poppler-utils
  else
    warn "Instale o poppler-utils manualmente: sem ele, PDFs caem no fallback de IA."
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
RELEASE_SRC=""

fetch_release() {
  command -v curl >/dev/null || die "curl é necessário."
  if [ -z "$VERSION" ]; then
    log "Procurando a última versão"
    VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    [ -n "$VERSION" ] || die "Não consegui descobrir a última versão. Use --version vX.Y.Z."
  fi
  local name="grana-${VERSION}-linux-${ARCH}.tar.gz"
  local base="https://github.com/$REPO/releases/download/$VERSION"

  log "Baixando $name"
  curl -fSL --progress-bar -o "$WORK/$name" "$base/$name"
  curl -fsSL -o "$WORK/$name.sha256" "$base/$name.sha256"

  log "Conferindo o sha256"
  (cd "$WORK" && sha256sum -c "$name.sha256") || die "sha256 não confere — download corrompido."

  tar -xzf "$WORK/$name" -C "$WORK"
  RELEASE_SRC="$WORK/grana"
}

build_from_source() {
  local repo_dir
  repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  [ -f "$repo_dir/mix.exs" ] || die "Rode --from-source a partir de um clone do repositório."

  command -v mix >/dev/null || die "Elixir não encontrado. Instale Erlang/OTP 28 e Elixir 1.18 (sugestão: https://mise.jdx.dev — o .tool-versions do projeto já fixa as versões)."
  local otp
  otp="$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().')"
  [ "$otp" -ge 28 ] 2>/dev/null || die "Erlang/OTP $otp encontrado; o Grana precisa do OTP 28."

  log "Compilando a release (isso leva alguns minutos)"
  (
    cd "$repo_dir"
    export MIX_ENV=prod
    mix local.hex --force --if-missing >/dev/null
    mix local.rebar --force --if-missing >/dev/null
    mix deps.get --only prod
    mix assets.deploy
    mix release --overwrite
  )
  RELEASE_SRC="$WORK/grana"
  cp -R "$repo_dir/_build/prod/rel/grana" "$RELEASE_SRC"
  cp "$repo_dir/.env.example" "$RELEASE_SRC/env.example"
  cp "$repo_dir/deploy/systemd/grana.service" "$RELEASE_SRC/grana.service"
}

install_system_deps
if [ "$MODE" = "source" ]; then build_from_source; else fetch_release; fi

log "Instalando em $APP_DIR"
if ! id grana >/dev/null 2>&1; then
  as_root useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin grana
fi
as_root install -d -o grana -g grana -m 700 "$DATA_DIR"
as_root install -d -m 755 "$APP_DIR"
as_root rm -rf "$APP_DIR"/*
as_root cp -R "$RELEASE_SRC"/. "$APP_DIR"/
as_root chmod -R go-w "$APP_DIR"

if [ ! -f "$ENV_FILE" ]; then
  log "Criando $ENV_FILE"
  as_root install -d -m 755 "$ENV_DIR"
  as_root install -m 640 -o root -g grana "$RELEASE_SRC/env.example" "$ENV_FILE"
fi

as_root install -m 644 "$RELEASE_SRC/grana.service" "$UNIT_FILE"
as_root systemctl daemon-reload
as_root systemctl enable grana >/dev/null

if [ "$MODE" = "source" ]; then
  UPDATE_CMD="git pull && ./deploy/install.sh --from-source"
else
  UPDATE_CMD="bash install.sh --update"
fi

# restart serve para instalar pela primeira vez e para atualizar (--update).
log "Iniciando o serviço"
as_root systemctl restart grana

cat <<MSG

Grana instalado e rodando em http://localhost:4000

Primeiro acesso: abra a URL do servidor e digite o código do setup, impresso no log.
O app escuta só nesta máquina: para abrir de outra, defina LISTEN_IP=0.0.0.0 em
$ENV_FILE (rede local) ou ponha um proxy com HTTPS na frente (veja o README).

    sudo journalctl -u grana | grep -A3 "configuração inicial"

Configuração:    $ENV_FILE   (opcional; tudo também pode ser feito pela tela)
Dados e banco:   $DATA_DIR
Atualizar:       $UPDATE_CMD   (faça um backup em Configurações antes)
Esqueci a senha: sudo -u grana $APP_DIR/bin/grana-reset-password
MSG
