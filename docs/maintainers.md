# 維護者指南

## 日常流程

```text
修改 src/ 或 targets/
→ git diff
→ 執行測試
→ 重新建置 dist/
→ 確認產物差異
→ 預覽同步
→ 必要時實際同步
→ 再次檢查
→ Commit
```

建議命令：

```powershell
.\AgentRules.cmd test
.\scripts\Build-AgentRules.ps1 -Target All
git diff --check
git diff -- dist
.\scripts\Sync-AgentRules.ps1 -Target All
```

只有需要更新本機 Agent 全域規則時才執行：

```powershell
.\scripts\Sync-AgentRules.ps1 -Target All -Apply
.\scripts\Check-AgentRules.ps1 -Target All
```

`Check` 在尚未部署時回傳 `1` 是正常結果；實際同步後應回傳 `0`。

## 測試

```powershell
.\AgentRules.cmd test
```

測試會建立 `tests/.sandbox/`，使用隔離來源、設定與目的地，涵蓋：

- 建置與產物格式。
- 預覽不寫入。
- 同步、備份與重複同步。
- 未知檔案保留。
- 備份清理與回復。
- 無效來源、Metadata 與白名單拒絕。

CI 會分別以 Windows PowerShell 5.1 與 PowerShell 7 執行相同測試，重新建置
`dist/`，並拒絕未提交的產物差異。

## Git 忽略與換行

`.gitignore` 排除：

```text
backups/        # 本機全域規則的歷史備份
*.tmp-*         # 同步交易暫存檔
tests/.sandbox/ # 隔離測試環境
```

`.gitattributes` 指定：

```text
Markdown、JSON、YAML、LICENSE：LF
PowerShell、CMD：CRLF
```

修改檔案時請保留既有編碼與換行。新文件與設定使用 UTF-8、LF；腳本使用
UTF-8 BOM、CRLF，以維持 Windows PowerShell 5.1 中文相容性。

## 新增 Agent Target

目前只實作 Codex 與 Antigravity。新增 Agent 時：

1. 在 `targets/` 新增 `<agent>-header.md`。
2. 在 `config/targets.json` 新增目標、輸出模式、目的地與白名單。
3. 在 `scripts/AgentRules.Common.ps1` 增加該輸出模式的確定性產生邏輯。
4. 增加隔離目的地測試，涵蓋預覽、同步、備份、重複同步與未知檔案保留。
5. 更新 README、架構文件與 CI。

不要只修改設定檔就假設新輸出模式已受支援。

## 發布

發布前至少確認：

```powershell
.\AgentRules.cmd test
.\AgentRules.cmd build
git diff --check
git status --short
```

並確認：

- GitHub Actions 全部通過。
- `dist/` 與來源一致。
- 完整 Git 歷史的敏感資訊掃描通過。
- 版本說明包含支援平台、主要變更與已知限制。
