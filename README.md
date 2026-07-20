# AI Agent 全域規範同步系統

集中維護一份 AI Agent 規範來源，透過可驗證、可重複執行的 PowerShell 腳本，建置並部署至不同 Agent 的全域規則目錄。

目前支援：

- Codex
- Antigravity

## 核心原則

- `src/` 是唯一人工維護來源；核心治理規則與按需 Skills 分開管理。
- `targets/` 只放各 Agent 專屬補充。
- `dist/` 與 Agent 全域規則都是建置或部署產物，不直接修改。
- 未指定 `-Apply` 時，同步腳本不得修改 Agent 全域目錄。
- 腳本只管理設定檔白名單內的檔案，不清空目錄、不碰認證、Session、快取、外掛或其他設定。
- 同步前備份實際將被覆蓋的核心檔或 Skill，同步後驗證 SHA-256。

## 目錄結構

```text
.
├─ src/
│  ├─ core.md
│  └─ skills/
│     └─ <skill-name>/
│        └─ SKILL.md
├─ targets/
│  ├─ codex-header.md
│  └─ antigravity-header.md
├─ config/
│  └─ targets.json
├─ scripts/
│  ├─ AgentRules.Common.ps1
│  ├─ AgentRules.Menu.ps1
│  ├─ Build-AgentRules.ps1
│  ├─ Check-AgentRules.ps1
│  └─ Sync-AgentRules.ps1
├─ AgentRules.cmd          # 雙擊啟動器
├─ dist/                  # 自動產生
└─ backups/               # 同步時自動產生，Git 忽略
```

## 唯一來源

共用規則只修改：

```text
src/core.md
src/skills/*/SKILL.md
```

Agent 專屬內容修改：

```text
targets/codex-header.md
targets/antigravity-header.md
```

不要直接修改：

```text
dist/**
%USERPROFILE%\.codex\AGENTS.md
%USERPROFILE%\.codex\skills\agent-rules-*\SKILL.md
%USERPROFILE%\.gemini\GEMINI.md
%USERPROFILE%\.gemini\config\skills\agent-rules-*\SKILL.md
```

部署端與來源不同時，以來源重新建置與部署，不把部署端內容反向合併回來源。

## 平台目的地

| Agent | 輸出方式 | 目的地 |
|---|---|---|
| Codex | 精簡核心＋原生 Skills | `%USERPROFILE%\.codex\AGENTS.md` 與 `%USERPROFILE%\.codex\skills\<skill-name>\SKILL.md` |
| Antigravity | 精簡核心＋原生 Skills | `%USERPROFILE%\.gemini\GEMINI.md` 與 `%USERPROFILE%\.gemini\config\skills\<skill-name>\SKILL.md` |

預設目的地與管理白名單集中在 `config/targets.json`。互動介面首次啟動時，會讓使用者選擇有限次數的自動偵測或手動輸入，並將確認後的全域目錄保存至 `%LOCALAPPDATA%\AgentRules\settings.json`。個人設定只覆寫目的地，不修改專案設定或管理白名單。

自動偵測不會遞迴掃描磁碟；每個 Agent 最多檢查 3 個已知候選位置。Codex 依序考慮 `CODEX_HOME` 與 `%USERPROFILE%\.codex`，Antigravity 依序考慮 `GEMINI_HOME` 與 `%USERPROFILE%\.gemini`。偵測失敗的項目會改由使用者輸入。

建置會驗證白名單，不允許設定額外檔案；同步器只管理本專案列出的 Skill，不會修改 `skills.json` 或其他既有 Skills。命令列明確傳入 `-ConfigPath` 時不載入個人設定，方便隔離測試或使用另一份完整設定。

## 核心規則與 Skills

`src/core.md` 只保留即使 Skill 未觸發也不得失效的治理底線，例如正確性、敏感資訊、權限、不可逆操作、既有變更保護與最低驗證要求。這些內容會始終載入至 `AGENTS.md` 或 `GEMINI.md`。

詳細的開發、文件、命令、Git、安全與測試流程放在 `src/skills/`，由 Codex 或 Antigravity 根據 `SKILL.md` 的 `description` 語意匹配後按需載入。Skills 能降低常駐 Context，但語意匹配不是強制治理邊界，因此不可漏掉的規則不得只放在 Skill。

每個 Skill 必須：

- 使用安全且唯一的小寫連字號目錄名稱。
- 包含 `SKILL.md`。
- 以 YAML frontmatter 開頭。
- `name` 必須與目錄名稱相同。
- 提供具體且涵蓋觸發情境的單行 `description`。

同一份 `src/skills/<skill-name>/SKILL.md` 會產生至兩平台；只有實際存在格式差異時才增加平台適配內容。

舊版曾部署的 `%USERPROFILE%\.codex\rules\*.md` 不在新版白名單內，因此新版同步不會修改或刪除它們。新版 `AGENTS.md` 已不再路由至這些檔案；確認兩平台 Skills 在新對話中正常觸發後，再由使用者明確決定是否清理舊產物。

## 環境需求

- Windows
- PowerShell 7，或 Windows PowerShell 5.1
- 不需要額外 PowerShell Module

建置產物使用 .NET 明確輸出 UTF-8（無 BOM）。腳本本身使用 UTF-8 BOM，避免 Windows PowerShell 5.1 將中文訊息誤判為 ANSI；PowerShell 7 亦可正常執行。

## 簡易操作

直接雙擊根目錄的：

```text
AgentRules.cmd
```

`AgentRules.cmd` 只負責以一致的參數啟動 PowerShell；互動介面與命令路由集中在
`scripts/AgentRules.Menu.ps1`。首次啟動且尚無個人設定時，會先顯示：

```text
1. 自動偵測
2. 手動輸入
0. 離開
```

完成設定後會開啟：

```text
1. 檢查狀態
2. 預覽同步
3. 同步全部
4. 僅同步 Codex
5. 僅同步 Antigravity
6. 執行測試
7. 預覽備份清理
8. 清理過期備份
9. 修改 Agent 目錄
10. 重新偵測 Agent 目錄
11. 回復備份檔案
0. 離開
```

「修改 Agent 目錄」可逐項輸入，直接按 Enter 會保留目前值；「重新偵測 Agent 目錄」會再次執行有限候選位置偵測，顯示結果並在確認後才覆寫設定。互動選單在實際同步前也會再次確認。

也可在 CMD 或 PowerShell 使用簡短命令：

```powershell
.\AgentRules.cmd check
.\AgentRules.cmd preview
.\AgentRules.cmd sync
.\AgentRules.cmd codex
.\AgentRules.cmd antigravity
.\AgentRules.cmd build
.\AgentRules.cmd test
```

其中 `sync`、`codex`、`antigravity` 是明確的實際部署命令，從命令列執行時不會再次詢問；若只想查看變更，使用 `preview`。

## 建置

建置只更新 `dist/`，不修改 Agent 全域目錄：

```powershell
.\scripts\Build-AgentRules.ps1 -Target All
```

單一目標：

```powershell
.\scripts\Build-AgentRules.ps1 -Target Codex
.\scripts\Build-AgentRules.ps1 -Target Antigravity
```

## 檢查

檢查來源、`dist/` 與目的地，不寫入任何檔案：

```powershell
.\scripts\Check-AgentRules.ps1 -Target All
```

退出碼：

| 退出碼 | 意義 |
|---:|---|
| 0 | 來源、`dist/` 與目的地一致 |
| 1 | 存在差異、缺少建置產物或尚未部署 |
| 2 | 設定或來源錯誤 |
| 3 | 無法存取目的地 |

## 預覽同步

預設只建置 `dist/` 並顯示目的地預計變更，不修改 Agent 全域目錄：

```powershell
.\scripts\Sync-AgentRules.ps1 -Target All
```

輸出會將檔案標示為「將新增」、「將更新」或「無變更」。

完整 log 會保留供檢查，最後以黃底黑字的 `[SUMMARY]` 顯示本次結論、差異數量與建議的下一步，且前後各保留一行空白。例如：

```text
[SUMMARY] 結論：預覽成功，共有 8 個檔案需要同步，本次未修改全域目錄。下一步：確認上方沒有 [ERROR] 後，選 3 同步全部。
```

## 實際同步

同步全部目標：

```powershell
.\scripts\Sync-AgentRules.ps1 -Target All -Apply
```

只同步單一 Agent：

```powershell
.\scripts\Sync-AgentRules.ps1 -Target Codex -Apply
.\scripts\Sync-AgentRules.ps1 -Target Antigravity -Apply
```

可用參數：

| 參數 | 說明 |
|---|---|
| `-Target Codex\|Antigravity\|All` | 選擇目標，預設 `All` |
| `-Apply` | 實際修改目的地；未指定時只預覽 |
| `-NoBackup` | 明確停用永久備份 |
| `-Force` | 保留給明確覆蓋情境；不會越過白名單與來源檢查 |
| `-ConfigPath` | 指定替代設定檔，主要供測試或可攜式部署使用 |

## 備份與回復

預設備份位於：

```text
backups/<yyyyMMdd-HHmmss-fff>/<target>/
```

只備份實際即將被覆蓋的受管理檔案；新增檔案不需要備份。

備份清理沿用 `AgentRules.cmd` 入口，預設保留最新 5 份，且只清理超過 30 天的其餘時間戳備份：

```powershell
# 只預覽，不刪除
.\AgentRules.cmd cleanup

# 依保留政策實際清理
.\AgentRules.cmd cleanup --apply
```

清理器只處理 `backups/<yyyyMMdd-HHmmss-fff>/`。名稱不符合格式的目錄（例如手動建立的 legacy 封存）會略過，不會自動刪除。

備份是單次同步前、僅包含當次被覆寫檔案的稀疏回滾集，不是完整時間點快照；回復時只會處理該備份實際包含且目前仍受管理的檔案，不會刪除其他檔案。

先列出可用備份：

```powershell
.\AgentRules.cmd restore
```

互動選單會依時間由新到舊顯示 `1.`、`2.`、`3.` 等序號，直接輸入序號即可選擇；選定後工具會固定使用對應的 BackupId 進行預覽與套用。

指定 BackupId 時預設只預覽，並依目前設定的 Agent 目的目錄顯示每個檔案的實際回復位置：

```powershell
.\AgentRules.cmd restore 20260720-194317-628
.\AgentRules.cmd restore 20260720-194317-628 --target Codex
```

確認預覽結果後才明確套用：

```powershell
.\AgentRules.cmd restore 20260720-194317-628 --target Codex --apply
```

`All` 代表該 BackupId 目錄內實際存在的所有 Agent 目標；一次同步全部目標時，各 Agent 可能分別產生不同 BackupId。套用前會先完成全部檔案的安全檢查與暫存，並把目的地現有內容建立為一份新的保護備份。任一檔案失敗時會嘗試回滾整次操作並驗證 SHA-256。

為避免把過時或非本工具管理的檔案寫回全域目錄，自動回復只接受 `yyyyMMdd-HHmmss-fff` 格式的標準備份，且所選目標內的每個檔案都必須仍在該目標目前的 `managedFiles` 白名單中。舊備份若在所選目標內包含已退出白名單的歷史路徑，會拒絕該次自動回復，仍可由維護者人工檢視。

## 日常維護流程

```text
修改 src/ 或 targets/
→ git diff
→ Build-AgentRules.ps1 -Target All
→ Check-AgentRules.ps1 -Target All
→ Sync-AgentRules.ps1 -Target All
→ Sync-AgentRules.ps1 -Target All -Apply
→ Check-AgentRules.ps1 -Target All
→ Commit
```

`Check` 在尚未部署時回傳 `1` 是正常結果；實際同步後應回傳 `0`。

## 安全行為

- 只操作 `targets.json` 內的第一階段白名單。
- 不刪除目的地未知檔案。
- 不清空 `.codex` 或 `.gemini`。
- 所有內容先寫入同目錄暫存檔並驗證，再取代目的檔案。
- 每個 Agent 個別執行；失敗時嘗試回復該 Agent 已變更的檔案。
- 必要來源缺失、設定錯誤、備份失敗或 SHA-256 不一致時立即停止。

## Git 忽略與檔案屬性

`.gitignore` 排除不應進入版本控制的本機產物：

```text
backups/        # 本機全域規則的歷史備份
*.tmp-*         # 同步交易使用的暫存檔
tests/.sandbox/ # 隔離測試產生的臨時環境
```

這些檔案都可由來源或執行流程重新產生，不應上傳。尤其 `backups/` 代表特定電腦的部署歷史，可能含有個人舊規則。

`.gitattributes` 不會忽略檔案；它指定 Git 如何正規化不同類型檔案的換行：

```text
Markdown、JSON：LF
PowerShell、CMD：CRLF
```

這可避免不同 Git 或編輯器設定只因換行不同而產生整份檔案的無意義差異。

## 專案規則

全域規則只放跨專案共用內容。特定專案的套件管理器、架構、測試命令與部署限制應放在專案內：

- Codex：專案根目錄或適用子目錄的 `AGENTS.md`，工作流程使用專案 Skill。
- Antigravity：固定專案規則使用 `<project>\.agents\rules\`，工作流程使用 `<project>\.agents\skills\`。

## 新增 Agent Target

第一階段只實作 Codex 與 Antigravity。未來新增 Agent 時：

1. 在 `targets/` 新增 `<agent>-header.md`。
2. 在 `config/targets.json` 新增目標、輸出模式、目的地與白名單。
3. 在 `AgentRules.Common.ps1` 新增該輸出模式的確定性產生邏輯。
4. 增加隔離目的地測試，驗證預覽、同步、備份、重複同步與未知檔案保留。

不要只修改設定檔就假設新輸出模式已受支援。
