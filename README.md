# aoccqa-rule-loader（規則整備器）

AOCCQA 測試案例產線 **Phase A 步驟 3「規則整備」** 的 Claude Agent Skill。

它的工作只有一件：把散落、已確認的產品規則，整理成一份**可靠、可追溯、按市場切片**的 **Rule Context**，交給下游產測試案例。它**不產測試案例、不替 PM/RD 做產品決策**——它是一道「把規則收乾淨、把不確定攤在檯面上」的整備工序。

---

## 目錄

- [1. 定義](#1-定義what)
- [2. 架構](#2-架構architecture)
- [3. 核心邏輯](#3-核心邏輯how)
- [4. 使用方式](#4-使用方式usage)
- [5. 安裝與打包](#5-安裝與打包)
- [6. 邊界與相依](#6-邊界與相依)

---

## 1. 定義（What）

### 1.1 要解決的問題

在 EC（Magento / AOM / EC 三層）的 QA 情境裡，一條需求能不能判 Pass/Fail，往往**不只看需求本身**，還取決於一堆「市場規則」：

- 國別 / 網站 / 語系 / 幣別 / 時區
- 身分別（Guest / Member / Admin / 系統）
- 產品或資料型別、狀態流轉與終態
- 後台設定 / 資格 / 排除規則
- 欄位對映 / 列舉值 / 空值處理
- Job / 排程 / 觸發條件
- 跨系統整合（前台 / 後台 / API / SFTP / 報表 / Email / 稽核）

這些規則常散落在不同來源、不同版本、甚至互相矛盾。若下游產案時邊產邊翻規則，會重複讀檔、臆測、把「A 市場的規則」誤套到「B 市場」。本 skill 就是把這一步**獨立成一道工序**，先把規則收斂成一份乾淨、帶出處的 context。

### 1.2 核心原則：每條可用規則須答四問

這是整個 skill 的判斷準繩。任何一條要交給下游的規則，都必須能回答：

1. **規則是什麼？**（What）
2. **在哪 / 何時適用？**（Where / When）
3. **哪份證據授權？**（By what evidence）
4. **是否可靠到能定義 Pass/Fail？**（Reliable enough?）

答不齊的，就不能標成「可用」，而要如實標為缺失 / 模糊 / 衝突。

### 1.3 三件固定產出

| 產出 | 作用 |
|---|---|
| **Normalized Rule Context** | 正規化後的原子規則清單，每條帶適用範圍、證據狀態、下游可用性 |
| **Rule Applicability Matrix** | 規則 × 市場/角色/型別/狀態 的適用性對照表 |
| **Missing / Conflict Rule Register** | 待補 / 衝突規則登記，含 owner、優先級、釐清問題 |

---

## 2. 架構（Architecture）

### 2.1 產線位置

```
步驟1              步驟2                步驟3           步驟4              步驟5                步驟6
fsd-parser  →  規格確認(QA+PM)  →  [rule-loader]  →  tc-generator  →  scenario-expander  →  quality-reviewer  → …
              （唯一必經人工關卡）    回饋節點①
```

- **上游**：
  - `aoccqa-fsd-parser`（步驟 1）產出 **Requirement Matrix**；
  - 步驟 2「規格確認」（QA＋PM，唯一必經的人工關卡）產出釐清結論。
- **本體**：本 skill（步驟 3），為**回饋節點 ①**——載入時若發現核心規則缺失/衝突，會回退步驟 2 由 PM/RD 補件。
- **下游**：`aoccqa-tc-generator`（步驟 4）直接引用 Requirement ID / Rule ID 產案，**不重讀原始檔**。

### 2.2 輸入 / 產出概觀

```
   [已確認 Requirement Matrix]  ─┐
   [In/Out of Scope 定義]       ─┤
   [市場規則庫 + Country/Type]  ─┘
                │
                ▼
        ┌───────────────────┐
        │  aoccqa-rule-loader │  ← 3 道執行閘門 + 6 段輸出契約
        └───────────────────┘
                │
                ▼
   1) Normalized Rule Context
   2) Rule Applicability Matrix
   3) Missing / Conflict Rule Register
   （＋ Source Register / Downstream Readiness）
```

### 2.3 檔案結構

| 檔案 | 說明 |
|---|---|
| `SKILL.md` | 技能本體。frontmatter（觸發描述）＋ 英文結構化指令 ＋ 繁中操作說明。這是實際被 agent 執行的規格。 |
| `agents/openai.yaml` | ChatGPT / Codex / API / Atlas 的介面設定（display name、預設提示、允許隱式呼叫）。 |
| `README.md` | 本文件，人類閱讀用的說明。 |
| `.gitignore` | 排除建置產物（`*.skill`）與暫存檔（`zi*`、`.DS_Store` 等）。 |

### 2.4 跨平台介面

`agents/openai.yaml` 讓同一份技能可在多個產品上以一致方式被呼叫：

- **平台**：`chatgpt`、`codex`、`api`、`atlas`
- **顯示名稱**：AOCCQA Rule Loader
- **允許隱式呼叫**：是（`allow_implicit_invocation: true`，命中觸發詞即可自動介入）

---

## 3. 核心邏輯（How）

skill 的執行分成「閘門 → 抽取正規化 → 判狀態 → 依契約輸出」四階段。以下為關鍵機制。

### 3.1 三道執行閘門（Execution Gates）

進入正式整備前，先過三關；任一關不通就停下如實回報，不硬做。

| 閘門 | 判斷 | 不通過時的動作 |
|---|---|---|
| **Gate 1｜規格就緒** | Requirement Matrix 是否已過步驟 2 確認 | 回報 `Not Ready for Rule Loading`，列出未解 Requirement ID |
| **Gate 2｜是否需載入規則** | Pass/Fail 是否取決於矩陣未定義的資訊 | 若矩陣已自足，回報 `No Additional Rule Loading Required`（**不製造空規則充數**） |
| **Gate 3｜來源可用性** | 必要來源是否可讀取 | 受影響規則標 `Missing` + `Blocked`，指名缺源與範圍，回報「待補規則」（**絕不借鄰近市場頂替**） |

### 3.2 來源權威與新鮮度（Authority & Freshness）

沒有使用者指定順序時，依權威由高到低評估（但**須同範圍同主題才能覆蓋**，不可機械式套用）：

1. 綁定當前版本的已確認決策
2. 現行核准規格 / 已確認 Requirement Matrix
3. 現行核准規則庫 / 設定定義
4. 現行核准 API / 對映 / Job / 排程 / 整合合約
5. 現行實作證據
6. 歷史文件與既有 Test Case

> 實作證據與既有 Test Case 只能是 `Reference Only`——**可以揭露落差，不能單獨建立新的 Expected Behavior**。較新來源只有在同範圍已核准並明確取代舊來源時才優先；否則兩者並存標 `Conflict`。

### 3.3 原子規則模型（Atomic Rule Model）

把複合敘述拆成「一個獨立變動的條件＋結果」為一條規則。國別 / 網站 / 角色 / 產品 / 狀態 / 設定 / 觸發 / 執行者 / 行為 / 排除 / 生效期 / 觀察點 / 來源，任一不同就拆。

每條原子規則必含：`Rule ID`、關聯 `Requirement ID`、維度、適用/排除範圍、條件/觸發、執行者/模式、預期行為、禁止行為、觀察點、生效期間、`Source ID`、證據狀態、下游可用性。

**保留字面值與有意義區別**（除非來源明確劃等號），例如絕不混同：

- `null` / 空字串 / 缺欄位 / `0` / `false` / 未回傳
- 自動排程 / 手動執行 / PM·RD 協助執行
- 隱藏 / 停用 / 不支援 / 超出範圍 / 不適用
- 軟刪除 / 硬刪除 / 過期 / 封存

### 3.4 證據狀態與下游可用性

每條規則**各指派恰好一個**證據狀態與一個下游可用性。

**證據狀態（Evidence Status）**

| 狀態 | 意義 |
|---|---|
| `Confirmed` | 明確、現行、已核准且內部一致 |
| `Derivable` | 由 Confirmed 規則直接組合，未產生新行為 |
| `Assumption Allowed` | 明確被允許的假設（附 owner 與標籤） |
| `Missing` | 必要規則或值缺失 → 待補規則 |
| `Ambiguous` | 單一來源允許實質不同的解讀 |
| `Conflict` | 適用來源規定互斥行為 |
| `Out of Scope` | 明確排除於當前工作 |
| `Not Applicable` | 已確認不適用 |
| `Reference Only` | 歷史/實作證據，無授權力 |

**下游可用性（Downstream Usability）**：`Usable` / `Partially Usable` / `Blocked` / `Excluded`。
> 鐵則：**沉默不等於禁止**；**絕不把 `Missing` 轉成 `Not Applicable`**。

### 3.5 工作流（6 步）

1. **推導 Rule Loading Scope**：只鎖會變動 Pass/Fail 的維度，不因出現在通用檢查表就擴張。
2. **建來源與權威登記**：盤點每個來源，標範圍、權威、缺附件、過期、草稿、不可取得。
3. **抽取並正規化原子規則**：拆複合、保留字面值、不確定等價標 `Ambiguous`（名詞不明時查名詞庫，見 §6）。
4. **解適用性**：逐條指明在哪/對誰/何時/何觸發/由誰執行/在哪觀察/在哪排除/還有何未知。
5. **偵測缺口與矛盾**：只提「答案會改變 Pass/Fail、適用性、test setup、所需協助或可觀察性」的問題，不給裝飾性問卷。
6. **準備決策導向釐清並判就緒度**：依決策型別路由 owner、標優先級。

**Owner 路由**

| 決策型別 | owner |
|---|---|
| 預期產品行為、國別上線、商業資格、範圍 | PM |
| API、對映、Job、log、狀態更新、觸發、實作合約 | RD |
| 測試執行範圍、測資可得性、環境存取 | QA |
| 跨 owner 決策 | PM + RD（敘明未解分工） |

**優先級**：`P0` 卡核心行為/主 Pass/Fail｜`P1` 卡重要市場·角色·狀態·資料·整合覆蓋｜`P2` 選配或低風險細節。

**下游就緒度**：`Ready` / `Conditionally Ready` / `Not Ready`（就緒度是針對 Rule Context，不是 Test Case 品質）。

### 3.6 輸出契約（依序 6 段）

1. **Rule Loading Summary**（矩陣版本、載入市場切片、各狀態計數、未解 P0/P1、就緒度）
2. **Source and Authority Register**
3. **Normalized Rule Context**
4. **Rule Applicability Matrix**（Applicability 只用 `Applicable`/`Not Applicable`/`Out of Scope`/`Missing`/`Conflict`）
5. **Missing and Conflict Rule Register**
6. **Downstream Readiness**（Usable / Blocked / Excluded Rule IDs、被允許假設、准許與禁止的下游範圍、下一個人工決策）

---

## 4. 使用方式（Usage）

### 4.1 觸發時機

當「已確認的 Requirement Matrix 之外，Pass/Fail 還取決於市場規則 / 身分別 / 型別 / 狀態流轉 / 後台設定 / 欄位對映 / Job 排程 / 跨系統整合」時使用。

**觸發詞**：規則載入、規則整備、整理市場規則、Rule Context、規則適用性 / 權威 / 新鮮度 / 衝突、載入當前市場規則。

### 4.2 必要輸入

1. **已確認 Requirement Matrix**（已過步驟 2；未解列與被允許假設須標記）
2. **In Scope / Out of Scope 定義**
3. **市場規則庫與 Country／Product Type 條件**（本輪明確提供或被允許的來源）

> **規則按市場載入**：從當前需求推導最小相關切片，**只取涉及的市場，不一次載入全部國別**（Token 與正確性考量）。

### 4.3 呼叫範例

在 Claude Code / Cowork 直接以自然語言觸發：

```text
用 aoccqa-rule-loader 針對這份已確認的 Requirement Matrix，
載入 IT/DE 兩個市場的規則，產出可追溯的 Rule Context，先不要產 Test Case。
```

OpenAI 系（ChatGPT / Codex / API / Atlas）預設提示（見 `agents/openai.yaml`）：

```text
Use $aoccqa-rule-loader to verify the supplied rule sources, resolve their
applicability per market, and produce a traceable Rule Context (Normalized Rule
Context, Rule Applicability Matrix, Missing/Conflict Rule Register) without
generating Test Cases.
```

### 4.4 完成準則（全部成立才算完成）

- Requirement Matrix 已過執行閘門；
- 只載相關規則與來源（按市場切片，未載全部國別）；
- 每條原子規則可追溯至 Requirement ID 與（可得時）Source ID；
- 字面技術值與有意義區別皆保留；
- 每條規則各一個證據狀態與一個下游可用性；
- 適用性 / 排除 / 生效期 / 未知彼此分明；
- 每個缺失 / 模糊 / 過期 / 不可取得 / 衝突規則都可見（待補規則已列出）；
- 沒有規則繼承自其他市場、專案、Test Case 或最佳實務；
- 沒有產生任何 Coverage Gap 或 Test Case 內容。

---

## 5. 安裝與打包

- **Claude Cowork / Claude Code**：將本 repo（含 `SKILL.md`）放入 skills 目錄，或以 skill 安裝流程載入。
- **OpenAI 系**：依 `agents/openai.yaml` 設定介面。
- **打包分享**：把含 `SKILL.md` 的 `aoccqa-rule-loader/` 目錄壓成 `.skill`（zip）即可（`*.skill` 已列入 `.gitignore`，屬建置產物，可隨時由 `SKILL.md + agents/` 重新打包）。
- **一鍵打包（Windows）**：執行 repo 內的 [`build-skill.ps1`](build-skill.ps1) 會把 `SKILL.md + agents/` 正規化為 LF、以 Windows `tar.exe` 壓成符合 ZIP 規範（正斜線）的 `aoccqa-rule-loader.skill`，並自我驗證：

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\build-skill.ps1
  ```

  > 註：勿用 PowerShell `Compress-Archive`——它會寫出反斜線路徑，部分 skill 安裝器會拒收。

---

## 6. 邊界與相依

### 6.1 邊界（絕不執行）

- 不解析原始 FSD / PRD / 截圖 / 流程圖 / Figma / API / 利害關係人訊息成 Requirement Matrix（那是 `aoccqa-fsd-parser`）；
- 不決定 PM/RD/QA 尚未確認的產品行為；
- 不從其他國別 / 網站 / 舊專案 / 既有 Test Case / 現行系統行為 / QA 慣例推論某市場規則；
- 不把「未提及」當成 `Disabled` / `Unsupported` / `Not Applicable`；
- 不產生 Coverage Gap、Test Case、Test Case ID、Test Data、Steps、Expected Result、優先級或執行順序；
- 不核准需求、規則或最終 QA 範圍。

> 交付物是**規則產物**，不是測試設計產物。

### 6.2 相依：知識庫與名詞庫（選用）

遇定義模糊、名詞不明、別名不確定、狀態值 / 欄位語意需釐清時，查 `aoccqa-knowledge-base`（特別是 **AOCCQA_glossary**，`Definition_AOCCQA_glossary.json`，權威名詞庫約 626 詞）。

**Token 鐵則：只查不載。**

1. 先讀 `references/kb_manifest.json`（小）決定「開哪檔、用哪 key」，再以 `jq`/`grep` 取符合的那幾筆；**勿 Read 整個大 JSON**（glossary 整檔約 120K tokens，jq 單筆僅數十 tokens）。
2. 大量讀取 / 分析交 subagent，只回濃縮結果。
3. 查不到就明講「庫內沒有」，不臆測、不整檔貼回。

此為**選用相依**：未安裝時規則維持 `Missing` / `Ambiguous`，不臆測。名詞庫只解語意、不改授權——glossary 條目不能單獨建立新的 Expected Behavior。

---

## 版本

初版。詳細操作規格與 frontmatter 觸發描述見 [`SKILL.md`](SKILL.md)。
