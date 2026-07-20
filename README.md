# AI Agent 全域規範同步系統

[![CI](https://github.com/SesamePasteNoodles/ai-agent-configs/actions/workflows/ci.yml/badge.svg)](https://github.com/SesamePasteNoodles/ai-agent-configs/actions/workflows/ci.yml)

集中維護一份 AI Agent 規範來源，透過可驗證、可重複執行的 PowerShell
腳本，建置並安全部署至不同 Agent 的全域規則目錄。

目前支援：

- Codex
- Antigravity

## 功能特色

- 以 `src/` 作為唯一人工維護來源。
- 將核心治理規則與按需載入的 Skills 分開管理。
- 預設只預覽；必須明確執行同步才會修改全域目錄。
- 只操作設定白名單內的檔案，不碰認證、Session、快取或外掛。
- 覆寫前建立備份，寫入後驗證 SHA-256。
- 提供隔離測試、備份清理與安全回復流程。

## 環境需求

- Windows
- Windows PowerShell 5.1 或 PowerShell 7
- 不需要額外 PowerShell Module

## 快速開始

複製專案後，直接雙擊：

```text
AgentRules.cmd
```

第一次啟動會協助偵測或設定 Codex 與 Antigravity 的全域目錄。設定保存在
`%LOCALAPPDATA%\AgentRules\settings.json`，不會寫回 Git。

也可以使用命令列：

```powershell
# 執行隔離測試
.\AgentRules.cmd test

# 預覽預計變更，不修改 Agent 全域目錄
.\AgentRules.cmd preview

# 確認預覽後，同步全部目標
.\AgentRules.cmd sync
```

> `sync`、`codex`、`antigravity`、`cleanup --apply` 與
> `restore --apply` 會立即修改檔案；執行前請先確認預覽結果。

## 常用命令

| 命令 | 用途 | 修改全域目錄 |
|---|---|:---:|
| `AgentRules.cmd check` | 檢查來源、產物與目的地 | 否 |
| `AgentRules.cmd preview` | 建置並預覽全部同步變更 | 否 |
| `AgentRules.cmd sync` | 同步 Codex 與 Antigravity | 是 |
| `AgentRules.cmd codex` | 只同步 Codex | 是 |
| `AgentRules.cmd antigravity` | 只同步 Antigravity | 是 |
| `AgentRules.cmd build` | 只更新 `dist/` | 否 |
| `AgentRules.cmd test` | 執行隔離測試 | 否 |
| `AgentRules.cmd cleanup` | 預覽備份清理 | 否 |
| `AgentRules.cmd restore` | 列出可回復備份 | 否 |

完整參數與退出碼請參閱[使用指南](docs/usage.md)。

## 運作方式

```text
src/ 與 targets/
        │
        ▼
確定性建置與驗證
        │
        ▼
      dist/
        │
        ▼
預覽 → 備份 → 寫入 → SHA-256 驗證
        │
        ▼
Codex / Antigravity 全域目錄
```

核心治理規則始終載入；詳細的開發、文件、命令、Git、安全與測試流程則由
各平台依 `SKILL.md` 的描述按需載入。

## 專案結構

```text
.
├─ src/          # 共用核心規則與 Skills，唯一人工維護來源
├─ targets/      # 各 Agent 專屬標頭
├─ config/       # 目的地預設值與受管理檔案白名單
├─ scripts/      # 建置、檢查、同步、備份與回復腳本
├─ tests/        # 隔離整合測試
├─ dist/         # 由來源確定性產生並提交的發布產物
└─ AgentRules.cmd
```

不要直接修改 `dist/` 或 Agent 全域目錄；部署端與來源不同時，應重新建置與
部署。

## 安全邊界

- 未指定套用參數時，同步與回復均只預覽。
- 不刪除目的地的未知檔案，也不清空 `.codex` 或 `.gemini`。
- 設定不允許越過受管理檔案白名單。
- 所有內容先寫入同目錄暫存檔並驗證，再取代目的檔案。
- 備份、設定錯誤或雜湊驗證失敗時會停止，並在需要時嘗試回滾。

詳細威脅邊界與回復限制請參閱[架構說明](docs/architecture.md)與
[備份及回復](docs/backup-restore.md)。

## 文件

- [使用指南](docs/usage.md)
- [備份、清理與回復](docs/backup-restore.md)
- [架構與安全模型](docs/architecture.md)
- [維護者指南](docs/maintainers.md)
- [貢獻指南](CONTRIBUTING.md)
- [安全政策](SECURITY.md)

## 開發

修改 `src/` 或 `targets/` 後執行：

```powershell
.\AgentRules.cmd test
.\AgentRules.cmd build
git diff --check
```

測試使用隔離目的地，不會修改真實 Agent 全域目錄。詳細流程請參閱
[維護者指南](docs/maintainers.md)。

## 授權

本專案採用 [MIT License](LICENSE)。
