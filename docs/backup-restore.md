# 備份、清理與回復

同步器預設在覆寫受管理檔案前建立備份。新增檔案因為沒有既有內容，不會建立
備份。

## 備份格式

預設備份位於：

```text
backups/<yyyyMMdd-HHmmss-fff>/<target>/
```

每份備份是單次同步前、只包含當次被覆寫檔案的稀疏回滾集，不是完整時間點
快照。因此回復只會處理該份備份實際包含的檔案，不會刪除其他檔案。

`backups/` 代表特定電腦的部署歷史，可能包含個人舊規則，已由 `.gitignore`
排除，不應提交或分享。

## 清理備份

預設保留最新五份，且只清理超過 30 天的其餘時間戳備份：

```powershell
# 只預覽，不刪除
.\AgentRules.cmd cleanup

# 依保留政策實際清理
.\AgentRules.cmd cleanup --apply
```

清理器只處理 `backups/<yyyyMMdd-HHmmss-fff>/`。名稱不符合格式的目錄，例如
手動建立的 legacy 封存，會略過而不自動刪除。

## 列出與預覽回復

列出可用備份：

```powershell
.\AgentRules.cmd restore
```

互動介面依時間由新到舊顯示序號。選定後，工具會固定使用對應的 BackupId
進行預覽與套用。

指定 BackupId 時仍預設只預覽，並依目前的 Agent 目的目錄顯示實際位置：

```powershell
.\AgentRules.cmd restore 20260720-194317-628
.\AgentRules.cmd restore 20260720-194317-628 --target Codex
```

## 套用回復

確認預覽結果後才明確套用：

```powershell
.\AgentRules.cmd restore 20260720-194317-628 --target Codex --apply
```

`All` 代表該 BackupId 目錄內實際存在的所有 Agent 目標。一次同步全部目標時，
各 Agent 可能分別產生不同 BackupId。

套用前會先：

1. 完成全部檔案的路徑與白名單檢查。
2. 暫存準備回復的內容。
3. 把目的地現有內容建立為新的保護備份。
4. 寫入並驗證 SHA-256。

任一檔案失敗時，工具會嘗試回滾整次操作並重新驗證。

## 回復限制

為避免把過時或非本工具管理的檔案寫回全域目錄，自動回復只接受：

- 名稱符合 `yyyyMMdd-HHmmss-fff` 的標準備份。
- 所選目標內的每個檔案目前仍在該目標的 `managedFiles` 白名單中。

如果舊備份包含已退出白名單的歷史路徑，整次自動回復會被拒絕。維護者仍可
在確認內容後人工處理，但不可用自動回復繞過目前的安全邊界。
