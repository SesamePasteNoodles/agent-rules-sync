---
name: agent-rules-git
description: Use when inspecting or operating Git, commits, branches, staging, push, pull requests, merge, rebase, tags, releases, or repository history.
---

<!--
此檔案由同步系統自動產生。
請勿直接修改，來源位於 AI Agent 規範專案。
-->

# Git 與版本控制規則

- 操作前檢查工作樹與相關差異，辨識並保留使用者既有或其他工作的修改。
- 不修改、還原、暫存或提交與目前需求無關的檔案與程式碼。
- 每次修改與 Commit 聚焦單一目的；提交訊息優先遵循專案規範，未指定時使用 Conventional Commits。
- 除非使用者明確要求，不主動建立 Commit、Push、Merge、Rebase、Force Push、Tag 或發布版本。
- 不改寫 Git Commit History；需要 Rebase、Force Push、Reset、清除未追蹤檔案或其他可能遺失內容的操作時，先說明影響並取得確認。
- 不以破壞性指令處理無關變更；無法安全避開時停止並向使用者說明衝突。
- 完成 Git 操作後回報實際分支、提交、推送或 PR 結果，不宣稱尚未完成的外部狀態。
