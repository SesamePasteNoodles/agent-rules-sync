# 貢獻指南

感謝你協助改善 AI Agent 全域規範同步系統。

## 開始之前

- 大型功能或新增 Agent Target 請先開 Issue 討論範圍。
- 安全漏洞不要開公開 Issue，請依 [SECURITY.md](SECURITY.md) 私下回報。
- 變更應維持目前的 Windows PowerShell 5.1 與 PowerShell 7 相容性。

## 來源與產物

人工維護的來源是：

```text
src/**
targets/**
config/targets.json
scripts/**
tests/**
```

`dist/` 是建置產物。請修改來源後執行建置，不要直接編輯 `dist/`：

```powershell
.\AgentRules.cmd build
```

請勿提交：

- `backups/`
- `tests/.sandbox/`
- 個人目的地設定
- 認證、Token、Session 或其他敏感資訊

## 驗證

提交 Pull Request 前執行：

```powershell
.\AgentRules.cmd test
.\AgentRules.cmd build
git diff --check
git diff -- dist
```

測試必須通過，且 `dist/` 必須與來源一致。若無法執行某項驗證，請在 PR 中
清楚說明原因與未驗證範圍。

## 變更原則

- 採取最小且足以完成需求的變更。
- 保留既有架構、編碼、換行與 PowerShell 風格。
- 不可繞過受管理檔案白名單、預覽、備份或雜湊驗證。
- 新行為應補上隔離測試與相關文件。
- 不可把不可漏掉的治理底線只放在按需 Skill。

詳細架構與維護流程請參閱：

- [架構與安全模型](docs/architecture.md)
- [維護者指南](docs/maintainers.md)

## Commit 與 Pull Request

Commit 建議使用 Conventional Commits：

```text
feat:
fix:
refactor:
docs:
test:
```

Pull Request 請說明：

- 變更目的與範圍。
- 使用者可觀察到的差異。
- 已執行的測試。
- 是否有破壞性變更或遷移需求。
