#!/bin/bash
# ============================================================
# ④ openssl で .htpasswd + Basic Auth 設定を生成するスクリプト
# 使い方: bash scripts/setup-htpasswd.sh
# ============================================================
set -euo pipefail

echo "🔐 Basic Auth (.htpasswd) セットアップ"
echo "============================================"

# --- 入力受付 ---
read -r -p "Basic Authのユーザー名: " AUTH_USER
read -r -s -p "Basic Authのパスワード: " AUTH_PASS
echo ""
read -r -s -p "パスワード確認: " AUTH_PASS2
echo ""

if [[ "$AUTH_PASS" != "$AUTH_PASS2" ]]; then
  echo "❌ パスワードが一致しません"
  exit 1
fi

if [[ -z "$AUTH_USER" || -z "$AUTH_PASS" ]]; then
  echo "❌ ユーザー名/パスワードを入力してください"
  exit 1
fi

# --- .htpasswd 生成 ---
HASH=$(openssl passwd -apr1 "$AUTH_PASS")
echo "${AUTH_USER}:${HASH}" > .htpasswd
echo "✅ .htpasswd 生成完了"

# --- .htaccess 生成/更新 ---
read -r -p "サーバー上の絶対パス (例: /home/xs123456/example.com/public_html): " REMOTE_PATH

cat > .htaccess_auth_snippet <<EOF
# === Basic Auth ===
AuthType Basic
AuthName "Restricted Area"
AuthUserFile ${REMOTE_PATH}/.htpasswd
Require valid-user
EOF

if [[ -f ".htaccess" ]]; then
  if grep -q "AuthType Basic" .htaccess; then
    echo "⚠️  .htaccess に既存のBasic Auth設定があります。手動で確認してください。"
  else
    cat .htaccess_auth_snippet >> .htaccess
    echo "✅ .htaccess を更新しました"
  fi
else
  cp .htaccess_auth_snippet .htaccess
  echo "✅ .htaccess を生成しました"
fi
rm -f .htaccess_auth_snippet

# --- GitHub Secrets への登録案内 ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 GitHub Secretsに以下を追加してください:"
echo ""
echo "  BASIC_AUTH_USER = ${AUTH_USER}"
echo "  BASIC_AUTH_PASS = (入力したパスワード)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 gh CLIで一括登録する場合:"
echo "   gh secret set BASIC_AUTH_USER --body \"${AUTH_USER}\""
echo "   gh secret set BASIC_AUTH_PASS"
