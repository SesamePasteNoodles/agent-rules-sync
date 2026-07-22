# 架構與安全模型

## 唯一來源

共用規則只修改：

```text
src/core.md
src/skills/*/SKILL.md
```

Agent 專屬內容只修改：

```text
targets/codex-header.md
targets/antigravity-header.md
```

以下皆為產物或部署目的地，不應直接修改：

```text
dist/**
%USERPROFILE%\.codex\AGENTS.md
%USERPROFILE%\.codex\skills\agent-rules-*\SKILL.md
%USERPROFILE%\.gemini\GEMINI.md
%USERPROFILE%\.gemini\antigravity\settings.json
%USERPROFILE%\.gemini\config\skills\agent-rules-*\SKILL.md
```

部署端與來源不同時，以來源重新建置與部署，不把部署端內容反向合併回來源。

## 平台目的地

| Agent | 輸出方式 | 目的地 |
|---|---|---|
| Codex | 精簡核心＋原生 Skills | `%USERPROFILE%\.codex\AGENTS.md` 與 `%USERPROFILE%\.codex\skills\<skill-name>\SKILL.md` |
| Antigravity | 精簡核心＋原生 Skills | `%USERPROFILE%\.gemini\GEMINI.md` 與 `%USERPROFILE%\.gemini\config\skills\<skill-name>\SKILL.md` |

Antigravity 另由 `targets/antigravity-settings.json` 產生並管理
`%USERPROFILE%\.gemini\antigravity\settings.json`，用於同步經專案審查的常規命令
白名單。此設定只套用至 Antigravity，不會寫入 Codex。

預設目的地、輸出模式與管理白名單集中在 `config/targets.json`。建置會驗證
白名單，不允許設定額外檔案；同步器只管理本專案列出的規則、Skill 與
Antigravity 命令白名單，不會修改 `skills.json` 或其他既有 Skills。

## 核心規則與 Skills

`src/core.md` 只保留即使 Skill 未觸發也不得失效的治理底線，例如正確性、
敏感資訊、權限、不可逆操作、既有變更保護與最低驗證要求。這些內容會始終
載入至 `AGENTS.md` 或 `GEMINI.md`。

詳細的開發、文件、命令、Git、安全與測試流程放在 `src/skills/`，由平台根據
`SKILL.md` 的 `description` 語意匹配後按需載入。語意匹配不是強制治理邊界，
因此不可漏掉的規則不得只放在 Skill。

每個 Skill 必須：

- 使用安全且唯一的小寫連字號目錄名稱。
- 包含 `SKILL.md`。
- 以 YAML frontmatter 開頭。
- `name` 與目錄名稱相同。
- 提供具體且涵蓋觸發情境的單行 `description`。

同一份來源會產生至兩平台；只有實際存在格式差異時才增加平台適配內容。

## 確定性產物

`dist/` 是由來源確定性產生的發布產物，保留在版本控制中，讓使用者能直接
檢閱最終會部署的內容。CI 會重新建置並確認 `dist/` 沒有未提交差異。

產物使用 .NET 明確輸出 UTF-8（無 BOM）。腳本使用 UTF-8 BOM，避免 Windows
PowerShell 5.1 將中文訊息誤判為 ANSI；PowerShell 7 亦可執行。

## 安全邊界

- 未指定 `-Apply` 時，同步不得修改 Agent 全域目錄。
- 只操作 `targets.json` 的受管理檔案白名單。
- 不刪除未知檔案，不清空 `.codex` 或 `.gemini`。
- 不碰認證、Session、快取、外掛或其他設定。
- 同步前備份即將覆寫的檔案，同步後驗證 SHA-256。
- 所有內容先寫入同目錄暫存檔並驗證，再取代目的檔案。
- 每個 Agent 個別執行；失敗時嘗試回復該 Agent 已變更檔案。
- 必要來源缺失、設定錯誤、備份失敗或雜湊不一致時立即停止。

這些措施降低誤寫與部分失敗風險，但不能取代作業系統權限、磁碟備份或人工
檢閱。使用者仍應先執行預覽，確認實際目的地與變更清單。

## 舊版產物

舊版曾部署的 `%USERPROFILE%\.codex\rules\*.md` 不在目前白名單內，新版同步
不會修改或刪除它們。確認兩平台 Skills 在新對話中正常觸發後，再由使用者
明確決定是否清理。

## 專案規則的責任邊界

本專案只放跨專案共用內容。特定專案的套件管理器、架構、測試命令與部署
限制應留在該專案：

- Codex：專案根目錄或適用子目錄的 `AGENTS.md`，工作流程使用專案 Skill。
- Antigravity：固定規則放在 `<project>\.agents\rules\`，工作流程放在
  `<project>\.agents\skills\`。
