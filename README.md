# 🚀 xserver-deploy-template

Xserver × GitHub Actions 自動デプロイ テンプレートリポジトリ

## ⚡ クイックスタート

```bash
# このテンプレートからリポジトリを作成 → Secrets登録 → clone まで全自動
bash scripts/init-repo.sh
```

## 📁 構成

```
.
├── .github/workflows/
│   ├── deploy-static.yml   # 静的サイト用
│   └── deploy-wp.yml       # WordPress テーマ用
├── scripts/
│   ├── init-repo.sh        # ⑦ gh CLI ワンコマンド
│   ├── setup-htpasswd.sh   # ④ Basic Auth設定
│   └── setup-template.sh   # ⑥ テンプレート登録
└── setup-ssh.sh            # ① SSH鍵生成
```

## 📝 必要なSecrets

| Secret名 | 説明 |
|----------|------|
| `SSH_HOST` | XserverホストURL |
| `SSH_PORT` | `10022`（Xserver固定） |
| `SSH_USER` | Xserverアカウント名 |
| `SSH_KEY` | SSH秘密鍵（全文） |
| `REMOTE_BASE_PATH` | デプロイ先パス |
