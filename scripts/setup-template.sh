#!/bin/bash
# ============================================================
# ⑥ このキットをGitHub Template Repositoryとして登録するスクリプト
#    一度だけ実行すれば、次回からは init-repo.sh が
#    テンプレートから自動クローンするようになります
#
# 使い方: bash scripts/setup-template.sh
# ============================================================
set -euo pipefail

cat <<'LOGO'
  🚀 Xserver Deploy Kit
  ── Template Repository セットアップ ──
LOGO

# ── 依存チェック ──────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "❌ gh CLI がインストールされていません"
  echo "   https://cli.github.com からインストールしてください"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "❌ gh CLI にログインしていません"
  echo "   gh auth login を実行してください"
  exit 1
fi

# ── GitHubユーザー名を取得 ────────────────────────────────
GH_USER=$(gh api user --jq '.login')
TEMPLATE_REPO="${GH_USER}/xserver-deploy-template"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo ""
echo "👤 GitHubユーザー: ${GH_USER}"
echo "📦 テンプレートリポジトリ名: xserver-deploy-template"
echo ""
read -r -p "このリポジトリ名で作成しますか？ [Y/n]: " ans
[[ "$ans" =~ ^[Nn]$ ]] && exit 0

# ── テンプレートリポジトリが既存か確認 ───────────────────
if gh repo view "${TEMPLATE_REPO}" &>/dev/null 2>&1; then
  echo ""
  echo "⚠️  既存のテンプレートリポジトリが見つかりました: ${TEMPLATE_REPO}"
  read -r -p "上書き更新しますか？ [y/N]: " overwrite
  if [[ "$overwrite" =~ ^[Yy]$ ]]; then
    REPO_EXISTS=true
  else
    echo "キャンセルしました"
    exit 0
  fi
else
  REPO_EXISTS=false
fi

# ── テンプレートリポジトリを作成 ─────────────────────────
if [[ "$REPO_EXISTS" == false ]]; then
  echo ""
  echo "📁 GitHubリポジトリを作成しています..."
  gh repo create "${TEMPLATE_REPO}" \
    --public \
    --description "🚀 Xserver自動デプロイ GitHub Template Repository" \
    --clone=false
  echo "  ✅ リポジトリ作成: https://github.com/${TEMPLATE_REPO}"
fi

# ── ローカルにクローンしてファイルをコピー ───────────────
WORK_DIR="/tmp/xserver-deploy-template-$$"
echo ""
echo "📂 ファイルをテンプレートリポジトリにコピーしています..."

gh repo clone "${TEMPLATE_REPO}" "${WORK_DIR}"

# 既存ファイルをクリア（.git以外）
find "${WORK_DIR}" -mindepth 1 -not -path "${WORK_DIR}/.git*" -delete 2>/dev/null || true

# ── コピーするファイル群 ──────────────────────────────────
mkdir -p "${WORK_DIR}/.github/workflows"
mkdir -p "${WORK_DIR}/scripts"

# ワークフロー
cp "${KIT_DIR}/.github/workflows/deploy-static.yml" \
   "${WORK_DIR}/.github/workflows/"
cp "${KIT_DIR}/.github/workflows/deploy-wp.yml" \
   "${WORK_DIR}/.github/workflows/"

# スクリプト
cp "${KIT_DIR}/scripts/init-repo.sh"       "${WORK_DIR}/scripts/"
cp "${KIT_DIR}/scripts/setup-htpasswd.sh"  "${WORK_DIR}/scripts/"
cp "${KIT_DIR}/scripts/setup-template.sh"  "${WORK_DIR}/scripts/"

# ルートスクリプト
cp "${KIT_DIR}/setup-ssh.sh" "${WORK_DIR}/"

# パーミッション設定
chmod +x "${WORK_DIR}/setup-ssh.sh"
chmod +x "${WORK_DIR}/scripts/"*.sh

# ── README生成 ────────────────────────────────────────────
cat > "${WORK_DIR}/README.md" <<MDEOF
# 🚀 xserver-deploy-template

Xserver × GitHub Actions 自動デプロイ テンプレートリポジトリ

## ⚡ クイックスタート

\`\`\`bash
# このテンプレートからリポジトリを作成 → Secrets登録 → clone まで全自動
bash scripts/init-repo.sh
\`\`\`

## 📁 構成

\`\`\`
.
├── .github/workflows/
│   ├── deploy-static.yml   # 静的サイト用
│   └── deploy-wp.yml       # WordPress テーマ用
├── scripts/
│   ├── init-repo.sh        # ⑦ gh CLI ワンコマンド
│   ├── setup-htpasswd.sh   # ④ Basic Auth設定
│   └── setup-template.sh   # ⑥ テンプレート登録
└── setup-ssh.sh            # ① SSH鍵生成
\`\`\`

## 📝 必要なSecrets

| Secret名 | 説明 |
|----------|------|
| \`SSH_HOST\` | XserverホストURL |
| \`SSH_PORT\` | \`10022\`（Xserver固定） |
| \`SSH_USER\` | Xserverアカウント名 |
| \`SSH_KEY\` | SSH秘密鍵（全文） |
| \`REMOTE_BASE_PATH\` | デプロイ先パス |
MDEOF

# ── .gitignore ────────────────────────────────────────────
cat > "${WORK_DIR}/.gitignore" <<'IGNORE'
.DS_Store
*.pyc
__pycache__/
.env
.htpasswd
node_modules/
IGNORE

# ── GitHubにpush ──────────────────────────────────────────
echo ""
echo "⬆️  GitHubにpushしています..."
cd "${WORK_DIR}"
git add .
git commit -m "🚀 Update xserver-deploy-template $(date +%Y-%m-%d)"
git push origin main
echo "  ✅ push完了"

# ── Template Repository フラグを有効化 ───────────────────
echo ""
echo "🏷️  テンプレートリポジトリとして設定しています..."
gh api \
  --method PATCH \
  "repos/${GH_USER}/xserver-deploy-template" \
  --field is_template=true \
  --silent
echo "  ✅ テンプレート設定完了"

# ── ワークフローを無効化 ──────────────────────────────────
# テンプレートリポジトリ自体ではデプロイが不要なため
echo ""
echo "🔕 ワークフローを無効化しています..."
gh workflow disable deploy-static.yml \
  --repo "${GH_USER}/xserver-deploy-template" 2>/dev/null && \
  echo "  ✅ deploy-static.yml を無効化" || \
  echo "  ⚠️  deploy-static.yml の無効化をスキップ"

gh workflow disable deploy-wp.yml \
  --repo "${GH_USER}/xserver-deploy-template" 2>/dev/null && \
  echo "  ✅ deploy-wp.yml を無効化" || \
  echo "  ⚠️  deploy-wp.yml の無効化をスキップ"

# ── 後片付け ──────────────────────────────────────────────
rm -rf "${WORK_DIR}"

# ── 完了 ─────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  🎉 テンプレートリポジトリ登録完了！             ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  URL: https://github.com/${TEMPLATE_REPO}"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "次回から init-repo.sh を実行すると"
echo "このテンプレートから自動クローンされます 🚀"
