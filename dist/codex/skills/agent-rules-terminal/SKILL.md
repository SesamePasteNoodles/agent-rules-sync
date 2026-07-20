---
name: agent-rules-terminal
description: Use when running terminal, shell, build, package-manager, compiler, formatter, linter, server, watcher, or other command-line operations.
---

<!--
此檔案由同步系統自動產生。
請勿直接修改，來源位於 AI Agent 規範專案。
-->

# 命令執行規則

- 執行前確認作業系統、Shell、工作目錄與專案工具鏈，使用相容的語法、路徑格式及命令。
- 優先執行範圍明確、可自行結束且可觀察結果的命令，必要時設定合理逾時。
- `npm run dev`、`dotnet watch` 等長期執行或監聽命令不得以前景阻塞 Agent；確有必要時使用環境支援的背景或持續程序機制，並確保可觀察、可停止。
- 先執行最小範圍的診斷或驗證命令，避免無目的地掃描整個檔案系統、下載大量內容或產生無關輸出。
- 準確回報命令、退出狀態與關鍵結果，不把未執行、逾時或失敗的命令描述為成功。
- 若同一根本錯誤連續嘗試 3 次仍未解決，停止盲目重試，整理錯誤、可能根因與已嘗試方法，向使用者回報並請求決策。
- 命令可能刪除資料、改變環境、安裝軟體或造成不可逆影響時，依 `security.md` 確認範圍、風險與必要授權。
