#!/bin/bash
# ============================================================
# ① SSH鍵生成 → 公開鍵をXserverへ登録するセットアップスクリプト
# 使い方: bash setup-ssh.sh <your_repo_name>
# ============================================================
set -euo pipefail

REPO=${1:-"my-project"}
KEY_NAME="github_actions_${REPO}"
KEY_PATH="$HOME/.ssh/${KEY_NAME}"

echo "🔑 SSH鍵ペアを生成します: ${KEY_NAME}"
echo "----------------------------------------------"

# --- 鍵生成 ---
if [[ -f "${KEY_PATH}" ]]; then
  echo "⚠️  既存の鍵が見つかりました: ${KEY_PATH}"
  read -r -p "上書きしますか？ [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "キャンセルしました。"; exit 0; }
fi

ssh-keygen -t ed25519 -C "github-actions@${REPO}" -f "${KEY_PATH}" -N ""

echo ""
echo "✅ 鍵生成完了！"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 【Step 1】以下の公開鍵をXserverのSSH設定に登録してください"
echo "   Xserverパネル → SSH設定 → 公開鍵登録"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat "${KEY_PATH}.pub"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 【Step 2】以下の秘密鍵をGitHub Secretsに登録してください"
echo "   Secret名: SSH_KEY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat "${KEY_PATH}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 登録が必要なGitHub Secrets 5つ:"
echo ""
echo "  SSH_HOST        = Xserverのホスト名 (例: sv12345.xserver.jp)"
echo "  SSH_PORT        = 10022  ← Xserverは非標準ポート"
echo "  SSH_USER        = Xserverのアカウント名 (例: xs123456)"
echo "  SSH_KEY         = 上記の秘密鍵（全文）"
echo "  REMOTE_BASE_PATH= デプロイ先パス (例: /home/xs123456/example.com/public_html)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ~/.ssh/config に追記
echo ""
read -r -p "🔧 ~/.ssh/config に設定を追記しますか？ [y/N]: " ans_config
if [[ "$ans_config" =~ ^[Yy]$ ]]; then
  read -r -p "Xserverホスト名を入力 (例: sv12345.xserver.jp): " ssh_host
  cat >> "$HOME/.ssh/config" <<EOF

# GitHub Actions deploy - ${REPO}
Host xserver-${REPO}
  HostName ${ssh_host}
  User xs000000
  Port 10022
  IdentityFile ${KEY_PATH}
  StrictHostKeyChecking no
EOF
  echo "✅ ~/.ssh/config を更新しました"
fi

echo ""
echo "🚀 次のステップ: bash scripts/init-repo.sh でGitHubリポジトリを作成"
