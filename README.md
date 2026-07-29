# aoccqa-rule-loader

AOCCQA 測試案例產線 **Phase A 步驟 3「規則整備」** 的 Claude Agent Skill。把散落、已確認的產品規則整理成一份可靠、可追溯、按市場切片的 **Rule Context**，交給下游產案。

## 產線位置

```
fsd-parser → 規格確認(QA+PM) → [rule-loader] → tc-generator → scenario-expander → quality-reviewer → …
```

- **上游**：`aoccqa-fsd-parser`（Requirement Matrix）＋ 步驟 2 規格確認結論。
- **本體**：本 skill。回饋節點 ①。
- **下游**：`aoccqa-tc-generator`（引用 Requirement ID / Rule ID，不重讀原始檔）。

## 輸入 / 產出

**輸入**：已確認的 Requirement Matrix、市場規則庫、Country／Product Type 條件。

**產出**（固定三件）：

1. Normalized Rule Context
2. Rule Applicability Matrix
3. Missing／Conflict Rule Register（待補／衝突規則）

## 邊界（不得執行）

不解析原始 FSD/PRD/截圖/Figma/API（屬 `aoccqa-fsd-parser`）；不替 PM/RD 決定產品行為；不產生 Coverage Gap、Test Case、Steps、Expected Result；不自行選擇互相衝突的規則；規則缺失時不得以其他市場的規則頂替（直接回報「待補規則」）。

## 相依

遇定義模糊或名詞不明時，查 `aoccqa-knowledge-base`（特別是 `AOCCQA_glossary` / `Definition_AOCCQA_glossary.json`），遵守「只查不載」的 Token 鐵則。此為選用相依，未安裝時規則維持 `Missing`／`Ambiguous`，不臆測。

## 內容

| 檔案 | 說明 |
|---|---|
| `SKILL.md` | 技能本體（frontmatter 觸發描述＋英文結構指令＋繁中說明） |
| `agents/openai.yaml` | ChatGPT / Codex / API / Atlas 介面設定 |

## 安裝

- **Claude Cowork / Claude Code**：將本 repo（含 `SKILL.md`）放入 skills 目錄，或以 skill 安裝流程載入。
- **打包**：把含 `SKILL.md` 的 `aoccqa-rule-loader/` 目錄壓成 `.skill`（zip）即可分享安裝。

## 版本

初版。內部版本資訊見 `SKILL.md`。
