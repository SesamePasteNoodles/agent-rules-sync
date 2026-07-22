# 使用指南

本文件說明互動介面、命令列操作、個人目的地設定與退出碼。架構設計請參閱
[architecture.md](architecture.md)，備份相關操作請參閱
[backup-restore.md](backup-restore.md)。

## 互動介面

直接雙擊專案根目錄的 `AgentRules.cmd`。它只負責以一致參數啟動
`scripts/AgentRules.Menu.ps1`。

第一次啟動且尚無個人設定時，可以：

```text
1. 自動偵測
2. 手動輸入
0. 離開
```

完成設定後，主選單提供：

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

互動介面在實際同步、清理或回復前會再次要求確認。

## 個人目的地設定

確認後的全域目錄保存在：

```text
%LOCALAPPDATA%\AgentRules\settings.json
```

個人設定只覆寫部署目的地，不修改專案設定或管理白名單。自動偵測不會遞迴
掃描磁碟；每個 Agent 最多檢查三個已知候選位置：

- Codex：`CODEX_HOME`、`%USERPROFILE%\.codex`
- Antigravity：`GEMINI_HOME`、`%USERPROFILE%\.gemini`

偵測失敗的項目會要求使用者手動輸入。「修改 Agent 目錄」可逐項輸入，
直接按 Enter 會保留目前值。

命令列明確傳入 `-ConfigPath` 時不會載入個人設定，適合隔離測試或使用另一份
完整設定。

## 簡短命令

```powershell
.\AgentRules.cmd check
.\AgentRules.cmd preview
.\AgentRules.cmd sync
.\AgentRules.cmd codex
.\AgentRules.cmd antigravity
.\AgentRules.cmd build
.\AgentRules.cmd test
```

`sync`、`codex` 與 `antigravity` 是明確的實際部署命令，從命令列執行時不會
再次詢問。若只想查看變更，請使用 `preview`。

## 建置

建置只更新 `dist/`，不修改 Agent 全域目錄：

```powershell
.\scripts\Build-AgentRules.ps1 -Target All
.\scripts\Build-AgentRules.ps1 -Target Codex
.\scripts\Build-AgentRules.ps1 -Target Antigravity
```

## 檢查

檢查來源、`dist/` 與目的地，不寫入檔案：

```powershell
.\scripts\Check-AgentRules.ps1 -Target All
```

| 退出碼 | 意義 |
|---:|---|
| 0 | 來源、`dist/` 與目的地一致 |
| 1 | 存在差異、缺少建置產物或尚未部署 |
| 2 | 設定或來源錯誤 |
| 3 | 無法存取目的地 |

尚未部署時回傳 `1` 是正常結果；實際同步後應回傳 `0`。

## 預覽同步

未指定 `-Apply` 時只更新 `dist/` 並顯示預計變更，不修改 Agent 全域目錄：

```powershell
.\scripts\Sync-AgentRules.ps1 -Target All
```

輸出會將檔案標示為「將新增」、「將更新」或「無變更」，最後以
`[SUMMARY]` 摘要差異數量與下一步。

## 實際同步

```powershell
# 同步全部
.\scripts\Sync-AgentRules.ps1 -Target All -Apply

# 同步單一 Agent
.\scripts\Sync-AgentRules.ps1 -Target Codex -Apply
.\scripts\Sync-AgentRules.ps1 -Target Antigravity -Apply
```

同步 Antigravity 時也會部署專案受管理的命令白名單到
`%USERPROFILE%\.gemini\antigravity\settings.json`。若目的檔已存在，系統會先
備份再取代；未列入 `config/targets.json` 的其他設定檔不會被修改。

| 參數 | 說明 |
|---|---|
| `-Target Codex\|Antigravity\|All` | 選擇目標，預設 `All` |
| `-Apply` | 實際修改目的地；未指定時只預覽 |
| `-NoBackup` | 明確停用永久備份 |
| `-Force` | 保留給明確覆蓋情境，不會越過白名單與來源檢查 |
| `-ConfigPath` | 指定替代設定檔，主要供測試或可攜式部署 |

## 日常使用建議

```text
檢查狀態
→ 預覽同步
→ 確認沒有錯誤或非預期目的地
→ 實際同步
→ 再次檢查狀態
```
