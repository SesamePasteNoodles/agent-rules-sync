# agent-rules-sync 專案規則

- 本專案是 AI Agent 規範同步系統；修改前必須先查閱 `README.md`、相關 `docs/` 文件與 `scripts/` 流程。
- 不得直接編輯 `.codex`、`.gemini` 或其他 Agent 全域目錄下的產出檔。
- 所有全域設定與規範變更，必須修改本專案內 `src/`、`targets/`、`config/` 等人工維護來源。
- 不得直接修改 `dist/`；完成來源變更後，使用 `.\AgentRules.cmd build` 產生發布產物。
- 變更後依風險執行 `.\AgentRules.cmd test`、`.\AgentRules.cmd build` 與 `git diff --check`。
