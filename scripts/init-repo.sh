#!/bin/bash
# ============================================================
# ⑦ gh CLI で1コマンド化
#    リポジトリ作成 → Secrets登録 → clone まで全自動
#
# 前提: gh auth login 済み / setup-ssh.sh 実行済み
# 使い方:
#   対話モード: bash scripts/init-repo.sh
#   引数モード: bash scripts/init-repo.sh <repo> <user> <host> <ssh_user> <path> <type>
# ============================================================
set -euo pipefail

# ──────────────────────────────
# 引数モード（AutoDeploy.appから呼び出し時）
# ──────────────────────────────
if [[ $# -eq 6 ]]; then
  REPO_NAME="$1"
  GH_USER="$2"
  SSH_HOST="$3"
  SSH_USER="$4"
  REMOTE_PATH="$5"
  SITE_TYPE="$6"
  SSH_PORT="10022"

  # 設定を保存
  CONF_FILE="$HOME/.xserver-deploy.conf"
  cat > "$CONF_FILE" <<CONF
XSERVER_SSH_HOST="${SSH_HOST}"
XSERVER_SSH_PORT="${SSH_PORT}"
XSERVER_SSH_USER="${SSH_USER}"
CONF
  chmod 600 "$CONF_FILE"

  echo "🚀 AutoDeployアプリからの実行"
  echo "  リポジトリ: ${GH_USER}/${REPO_NAME}"
  echo "  サーバー: ${SSH_HOST}"
  echo "  種別: ${SITE_TYPE}"
  echo ""
  # 引数モードではBasic Authをスキップ
  USE_BASIC_AUTH="n"
else

# ──────────────────────────────
# ロゴ表示
# ──────────────────────────────
cat <<'LOGO'
  🚀 Xserver Auto Deploy Kit
  ══════════════════════════════
  GitHub × Xserver 自動デプロイ
  ══════════════════════════════
LOGO

# ──────────────────────────────
# 依存チェック
# ──────────────────────────────
for cmd in gh ssh-keygen openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ ${cmd} がインストールされていません"
    exit 1
  fi
done

# ──────────────────────────────
# 設定ファイルの読み込み/保存
# ~/.xserver-deploy.conf
# ──────────────────────────────
CONF_FILE="$HOME/.xserver-deploy.conf"

# 既存の設定を読み込む
SAVED_SSH_HOST=""
SAVED_SSH_PORT="10022"
SAVED_SSH_USER=""

if [[ -f "$CONF_FILE" ]]; then
  source "$CONF_FILE"
  SAVED_SSH_HOST="${XSERVER_SSH_HOST:-}"
  SAVED_SSH_PORT="${XSERVER_SSH_PORT:-10022}"
  SAVED_SSH_USER="${XSERVER_SSH_USER:-}"
fi

# ──────────────────────────────
# 入力受付
# ──────────────────────────────
echo ""
echo "📝 プロジェクト情報を入力してください"
echo "──────────────────────────────────────"

read -r -p "リポジトリ名 (例: my-awesome-site): " REPO_NAME
if [[ -z "$REPO_NAME" ]]; then
  echo "❌ リポジトリ名は必須です"; exit 1
fi

# GitHubユーザー名は自動取得
GH_USER=$(gh api user --jq '.login' 2>/dev/null || true)
if [[ -z "$GH_USER" ]]; then
  read -r -p "GitHubユーザー名: " GH_USER
else
  echo "👤 GitHubユーザー名: ${GH_USER} (自動取得)"
fi

echo ""
echo "📡 Xserverの接続情報を入力してください"
echo "──────────────────────────────────────"

# SSH_HOST
if [[ -n "$SAVED_SSH_HOST" ]]; then
  read -r -p "SSH_HOST [${SAVED_SSH_HOST}]: " SSH_HOST_INPUT
  SSH_HOST="${SSH_HOST_INPUT:-$SAVED_SSH_HOST}"
else
  read -r -p "SSH_HOST (例: sv12345.xserver.jp): " SSH_HOST
fi

# SSH_PORT
if [[ -n "$SAVED_SSH_PORT" ]]; then
  read -r -p "SSH_PORT [${SAVED_SSH_PORT}]: " SSH_PORT_INPUT
  SSH_PORT="${SSH_PORT_INPUT:-$SAVED_SSH_PORT}"
else
  read -r -p "SSH_PORT [10022]: " SSH_PORT
  SSH_PORT="${SSH_PORT:-10022}"
fi

# SSH_USER
if [[ -n "$SAVED_SSH_USER" ]]; then
  read -r -p "SSH_USER [${SAVED_SSH_USER}]: " SSH_USER_INPUT
  SSH_USER="${SSH_USER_INPUT:-$SAVED_SSH_USER}"
else
  read -r -p "SSH_USER (例: xs123456): " SSH_USER
fi

# 設定をファイルに保存
cat > "$CONF_FILE" <<CONF
XSERVER_SSH_HOST="${SSH_HOST}"
XSERVER_SSH_PORT="${SSH_PORT}"
XSERVER_SSH_USER="${SSH_USER}"
CONF
chmod 600 "$CONF_FILE"
echo "  ✅ Xserver接続情報を保存しました"

echo ""
echo "🗂  デプロイ先パスを入力してください"
echo "──────────────────────────────────────"
read -r -p "REMOTE_BASE_PATH (例: /home/xs123456/example.com/public_html): " REMOTE_PATH

echo ""
echo "📦 サイト種別を選んでください"
echo "  1) 静的サイト (HTML/CSS/JS)"
echo "  2) WordPress テーマ"
read -r -p "選択 [1/2]: " SITE_TYPE_NUM
case "$SITE_TYPE_NUM" in
  2) SITE_TYPE="wp";;
  *) SITE_TYPE="static";;
esac

USE_BASIC_AUTH=""
fi # 引数モードのelse終了

# ──────────────────────────────
# 既存のSSH鍵を使用
# setup-ssh.sh で生成した鍵を使い回す
# ──────────────────────────────
echo ""
echo "🔑 SSH鍵を検索しています..."

# ~/.ssh/ にある github_actions_ で始まる鍵を検索
KEY_LIST=$(ls "$HOME/.ssh/github_actions_"*.pub 2>/dev/null | sed 's/\.pub$//' || true)

if [[ -z "$KEY_LIST" ]]; then
  echo "❌ SSH鍵が見つかりません"
  echo "   先に bash setup-ssh.sh を実行してください"
  exit 1
fi

# 鍵が1つだけの場合はそのまま使用
KEY_COUNT=$(echo "$KEY_LIST" | wc -l | tr -d ' ')

if [[ "$KEY_COUNT" -eq 1 ]]; then
  KEY_PATH="$KEY_LIST"
  echo "  ✅ SSH鍵を使用: $(basename ${KEY_PATH})"
else
  # 複数ある場合は選択
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔑 使用するSSH鍵を選んでください:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  # macOS互換: mapfileの代わりにwhileで配列に格納
  KEYS=()
  while IFS= read -r line; do
    KEYS+=("$line")
  done <<< "$KEY_LIST"
  for i in "${!KEYS[@]}"; do
    echo "  $((i+1))) $(basename ${KEYS[$i]})"
  done
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  read -r -p "番号を選んでください [1-${#KEYS[@]}]: " key_num
  KEY_PATH="${KEYS[$((key_num-1))]}"
  echo "  ✅ SSH鍵を使用: $(basename ${KEY_PATH})"
fi

SSH_KEY=$(cat "${KEY_PATH}")

# ──────────────────────────────
# テンプレートリポジトリを選択
# ──────────────────────────────
echo ""
echo "📋 テンプレートリポジトリを検索しています..."

# 自分のテンプレートリポジトリ一覧を取得（privateも含む）
TEMPLATE_LIST=$(gh repo list "${GH_USER}" \
  --json name,isTemplate \
  --jq '.[] | select(.isTemplate==true) | .name' \
  --limit 100 2>/dev/null | sed "s|^|${GH_USER}/|" || true)

TEMPLATE_REPO=""
FROM_TEMPLATE=false

if [[ -z "$TEMPLATE_LIST" ]]; then
  # テンプレートが1つもない場合
  echo "  ⚠️  テンプレートリポジトリが見つかりません"
  echo "  💡 bash scripts/setup-template.sh で登録できます"
  echo ""
  read -r -p "テンプレートなしで空リポジトリを作成しますか？ [Y/n]: " no_tmpl
  [[ "$no_tmpl" =~ ^[Nn]$ ]] && { echo "キャンセルしました"; exit 0; }

else
  # テンプレート一覧を番号付きで表示
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 利用可能なテンプレートリポジトリ:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # 配列に格納
  # macOS互換
  TEMPLATES=()
  while IFS= read -r line; do
    TEMPLATES+=("$line")
  done <<< "$TEMPLATE_LIST"

  # 番号付きで表示
  for i in "${!TEMPLATES[@]}"; do
    echo "  $((i+1))) ${TEMPLATES[$i]}"
  done
  echo "  $((${#TEMPLATES[@]}+1))) テンプレートを使わない（空リポジトリ）"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  while true; do
    read -r -p "番号を選んでください [1-$((${#TEMPLATES[@]}+1))]: " tmpl_num
    if [[ "$tmpl_num" =~ ^[0-9]+$ ]] && \
       [[ "$tmpl_num" -ge 1 ]] && \
       [[ "$tmpl_num" -le $((${#TEMPLATES[@]}+1)) ]]; then
      break
    fi
    echo "  ⚠️  1〜$((${#TEMPLATES[@]}+1)) の数字を入力してください"
  done

  if [[ "$tmpl_num" -le "${#TEMPLATES[@]}" ]]; then
    TEMPLATE_REPO="${TEMPLATES[$((tmpl_num-1))]}"
    FROM_TEMPLATE=true
    echo "  ✅ テンプレート選択: ${TEMPLATE_REPO}"
  else
    echo "  📦 テンプレートなしで作成します"
  fi
fi

# ──────────────────────────────
# リポジトリ作成
# ──────────────────────────────
echo ""
echo "📁 GitHubリポジトリを作成しています..."

if [[ "$FROM_TEMPLATE" == true ]]; then
  gh repo create "${GH_USER}/${REPO_NAME}" \
    --template "${TEMPLATE_REPO}" \
    --private \
    --clone=false
else
  gh repo create "${GH_USER}/${REPO_NAME}" \
    --private \
    --clone=false
fi
echo "  ✅ リポジトリ作成: https://github.com/${GH_USER}/${REPO_NAME}"

# ──────────────────────────────
# Secrets 5つを登録
# ──────────────────────────────
echo ""
echo "🔐 GitHub Secrets を登録しています..."
FULL_REPO="${GH_USER}/${REPO_NAME}"

gh secret set SSH_HOST        --repo "${FULL_REPO}" --body "${SSH_HOST}"
echo "  ✅ SSH_HOST"
gh secret set SSH_PORT        --repo "${FULL_REPO}" --body "${SSH_PORT}"
echo "  ✅ SSH_PORT"
gh secret set SSH_USER        --repo "${FULL_REPO}" --body "${SSH_USER}"
echo "  ✅ SSH_USER"
gh secret set SSH_KEY         --repo "${FULL_REPO}" --body "${SSH_KEY}"
echo "  ✅ SSH_KEY"
gh secret set REMOTE_BASE_PATH --repo "${FULL_REPO}" --body "${REMOTE_PATH}"
echo "  ✅ REMOTE_BASE_PATH"

# ── Basic Auth（任意）────────────────────────────────────
echo ""
if [[ -z "${USE_BASIC_AUTH:-}" ]]; then
  read -r -p "🔐 ベーシック認証を設定しますか？ [y/N]: " USE_BASIC_AUTH
fi
if [[ "$USE_BASIC_AUTH" =~ ^[Yy]$ ]]; then
  read -r -p "  ユーザー名: " BASIC_USER
  read -r -s -p "  パスワード: " BASIC_PASS
  echo ""
  gh secret set BASIC_AUTH_USER --repo "${FULL_REPO}" --body "${BASIC_USER}"
  echo "  ✅ BASIC_AUTH_USER"
  gh secret set BASIC_AUTH_PASS --repo "${FULL_REPO}" --body "${BASIC_PASS}"
  echo "  ✅ BASIC_AUTH_PASS"
else
  echo "  ⏭  ベーシック認証はスキップ"
fi

# ──────────────────────────────
# ワークフローファイルをコピー
# テンプレートに関わらず必ずコピーする
# ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_SRC="${SCRIPT_DIR}/../.github/workflows"
WORKFLOWS_DEST="${REPO_NAME}/.github/workflows"

gh repo clone "${GH_USER}/${REPO_NAME}" "${REPO_NAME}"

mkdir -p "${WORKFLOWS_DEST}"

if [[ "$SITE_TYPE" == "wp" ]]; then
  cp "${WORKFLOWS_SRC}/deploy-wp.yml" "${WORKFLOWS_DEST}/"
  rm -f "${WORKFLOWS_DEST}/deploy-static.yml"
  echo "  ✅ deploy-wp.yml をコピー"
else
  cp "${WORKFLOWS_SRC}/deploy-static.yml" "${WORKFLOWS_DEST}/"
  rm -f "${WORKFLOWS_DEST}/deploy-wp.yml"
  echo "  ✅ deploy-static.yml をコピー"
fi

# READMEが存在しない場合のみ生成
if [[ ! -f "${REPO_NAME}/README.md" ]]; then
  cat > "${REPO_NAME}/README.md" <<MDEOF
# ${REPO_NAME}

🚀 Xserver Auto Deploy - $(date +%Y-%m-%d)

## デプロイ
- ブランチ: \`main\`
- サーバー: Xserver (\`${SSH_HOST}\`)
- 種別: ${SITE_TYPE}
- デプロイ先: \`${REMOTE_PATH}\`

## セットアップ済みSecrets
- \`SSH_HOST\` / \`SSH_PORT\` / \`SSH_USER\` / \`SSH_KEY\` / \`REMOTE_BASE_PATH\`
MDEOF
  echo "  ✅ README.md を生成"
else
  echo "  ✅ README.md は既存のものを使用"
fi

# 最初のコミット&プッシュ
cd "${REPO_NAME}"
git add .
git commit -m "🚀 Initial setup: Xserver auto deploy"
git push origin main
cd ..

# ──────────────────────────────
# 完了表示
# ──────────────────────────────
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  🎉 セットアップ完了！                     ║"
echo "╠════════════════════════════════════════════╣"
echo "║  リポジトリ: ${GH_USER}/${REPO_NAME}"
echo "║  種別: ${SITE_TYPE}"
echo "║  push → main で自動デプロイ開始 🚀        ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "📂 クローン済み: ./${REPO_NAME}"
echo "👉 cd ${REPO_NAME} で作業開始してください"
