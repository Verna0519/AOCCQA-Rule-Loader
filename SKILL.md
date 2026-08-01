---
name: aoccqa-rule-loader
metadata:
  version: 1.0.0
description: AOCCQA 測試案例產線 Phase A 步驟 3「規則整備」。當已確認的 Requirement Matrix 之外，Pass/Fail 或適用性還取決於市場規則（國別/網站/語系/幣別/時區）、身分別（Guest/Member/Admin/系統）、產品或資料型別、狀態流轉、後台設定/資格/排除、欄位對映/列舉/空值、Job/排程/觸發、或跨系統整合（前台/後台/API/SFTP/報表/Email/稽核）時，必須使用此 skill 整理出「可追溯的 Rule Context」。輸入為已確認的 Requirement Matrix、市場規則庫、Country／Product Type 條件；產出固定三件：Normalized Rule Context、Rule Applicability Matrix、Missing／Conflict Rule Register（待補／衝突規則）。規則按市場載入，只取當前需求涉及的市場，不一次載入全部國別；遇定義模糊或名詞不明時查 aoccqa-knowledge-base 與 AOCCQA_glossary。觸發詞：規則載入、規則整備、整理市場規則、Rule Context、規則適用性/權威/新鮮度/衝突、載入當前市場規則。不解析原始 FSD/PRD/截圖/Figma/API（屬 aoccqa-fsd-parser）；不替 PM/RD 決定產品行為；不產生 Coverage Gap、Test Case、Steps、Expected Result；不自行選擇互相衝突的規則；規則缺失時不得以其他市場的規則頂替。
---

# AOCCQA Rule Loader（規則整備器）

把散落的已確認規則，整理成可靠、可追溯、按市場切片的 **Rule Context**。每條可用規則須答四問：

1. 規則是什麼？
2. 在哪/何時適用？
3. 哪份證據授權？
4. 是否可靠到能定義 Pass/Fail？

## Pipeline position（產線位置）

- 步驟 3｜規則載入，回饋節點 **①**。
- 上游：步驟 1 `aoccqa-fsd-parser`（Requirement Matrix）→ 步驟 2「規格確認」（QA＋PM，唯一必經人工關卡）取得釐清結論。
- 下游：Rule Context 交步驟 4 `aoccqa-tc-generator`（引用 Requirement ID / Rule ID，不重讀原始檔）。
- 回退：載入時發現核心規則缺失或衝突 → 回報並回退步驟 2 由 PM/RD 補件，不自行決定。

## Responsibility boundary（責任邊界）

**只做（規則整備）：** 判斷是否需額外載入；盤點並排序被允許來源、建來源與權威登記；只載當前 Requirement 範圍相關規則（按市場切片）；複合敘述拆成原子規則、保留字面技術值與有意義區別；解適用/排除/生效期/觸發/執行者/觀察點；揭露缺失、模糊、衝突、過期、不可取得的規則；把「需決策」問題路由給正確 owner（PM/RD/QA）；為每條原子規則指派證據狀態與下游可用性。

**絕不做（Never，安全邊界，逐條遵守）：**

- 不解析原始 FSD、PRD、截圖、流程圖、Figma、API 或利害關係人訊息成 Requirement Matrix（那是 `aoccqa-fsd-parser`）；
- 不決定 PM/RD/QA 尚未確認的產品行為；
- 不從其他國別、其他網站、舊專案、既有 Test Case、現行系統行為或 QA 慣例推論某市場規則；
- 不把「未提及（not mentioned）」當成 `Disabled`／`Unsupported`／`Not Applicable`；
- 不產生 Coverage Gap、Test Case、Test Case ID、Test Data、Steps、Expected Result、優先級或執行順序；
- 不核准需求、規則或最終 QA 範圍。

交付物是規則產物，非測試設計產物。

## Required inputs（必要輸入）

1. **已確認 Requirement Matrix**：已過步驟 2 規格確認；仍有未解列與被允許假設須明確標記。
2. **In Scope / Out of Scope 定義**：本輪範圍界線。
3. **市場規則庫與 Country／Product Type 條件**：本輪明確提供或被允許的規則來源。

來源可含：核准市場對照表、PM/RD/QA 決策、網站設定定義、資格規則、狀態流轉規則、API 合約、欄位對映、匯入/匯出 schema、Cron/Job 定義、排程、整合規格、核准知識庫條目。

> 不索取或載入整個規則庫。**規則按市場載入**：從當前 Requirement Matrix 推導最小相關切片，只取當前需求涉及市場，不一次載入全部國別。

## Execution gates（執行閘門）

### Gate 1：規格就緒

Requirement Matrix 未過步驟 2 規格確認 → 停止，回報 `Not Ready for Rule Loading`，列未解 Requirement ID。只有矩陣已記錄「假設值、誰允許、影響範圍、下游如何標示」四項時，才可帶假設繼續。不得把未標記的自行解讀當成規則。

### Gate 2：是否需載入規則

只有當 Pass/Fail 或適用性取決於 Requirement Matrix 未完整定義的資訊時才載外部規則，例如：國別/網站/語言/locale/幣別/時區；Guest/Member/Admin/operator/系統執行者；產品/付款/訂單/退貨/報表/資料型別；狀態/轉移/終態/重複執行/禁止動作；後台設定/範圍繼承/資格/排除；欄位對映/列舉/null 空值/匯入匯出/資料完整性；自動 Job/手動動作/排程/處理窗/觸發；前台/後台/API/SFTP/報表/Email/稽核或其他整合。

若已確認 Requirement Matrix 對當前範圍已自足，回傳：

```text
Rule Loading Result: No Additional Rule Loading Required
Reason: The confirmed Requirement Matrix is self-contained for the current scope.
Downstream Readiness: Ready
```

不得為讓此階段看似有執行而製造空規則。

### Gate 3：來源可用性

以可讀來源繼續；某必要來源缺失時，將受影響規則標 `Missing` 且 `Blocked`，指名不可得來源與受影響範圍，直接回報「**待補規則**」。**絕不借用鄰近市場的答案頂替。**

## Source authority and freshness（來源權威與新鮮度）

優先採用使用者明確提供的權威順序；否則依下列評估（不得機械式套用——高階來源須覆蓋相同範圍與主題才算數，例如 PM 對國別上線的決策不能推翻 API 合約對欄位型別的定義）：

1. 綁定當前需求版本的已確認決策；
2. 現行核准規格或已確認 Requirement Matrix；
3. 現行核准規則庫或設定定義；
4. 現行核准 API／對映／Job／排程／整合合約；
5. 現行實作證據；
6. 歷史文件與既有 Test Case。

每份來源保留：來源 ID、標題、位置、owner、來源型別；版本或最後更新日；核准狀態；生效與失效日；適用範圍；supersedes / superseded-by；可存取性與缺附件。

實作證據與 Test Case 僅作 `Reference Only`——可揭露落差或缺漏，**不能單獨建立新 Expected Behavior**。只有較新來源在相同範圍已核准且明確取代舊來源時才優先採用；否則兩者並存標 `Conflict`。

## Knowledge-base & glossary integration（知識庫與名詞庫整合）

遇定義模糊、名詞不明、別名不確定、狀態值/欄位語意需釐清時，查 `/aoccqa-knowledge-base`（若已安裝且被允許），特別是 **AOCCQA_glossary**（`Definition_AOCCQA_glossary.json`，權威名詞庫約 626 詞）。

**Token 鐵則（務必遵守，對齊 aoccqa-knowledge-base）：只查不載。**

1. 先讀 `references/kb_manifest.json`（小）決定「開哪檔、用哪 key」，再用 bash `jq`/`grep` 取符合的那幾筆；**勿 Read 整個大 JSON**（glossary 整檔約 120K tokens，jq 單筆約數十 tokens）。
2. 大量讀取/分析交 subagent，只回濃縮結果。
3. 查不到就明講「庫內沒有」，不臆測，不整檔貼回。

jq 食譜（`KB=<aoccqa-knowledge-base 路徑>/references`）：

```bash
# 名詞/狀態值/欄位/公式定義（AOCCQA_glossary；欄位 term/aliases/definition_zh/detail/sources）
jq '.terms[]|select(.term=="X" or (.aliases[]?=="X"))' "$KB/Definition_AOCCQA_glossary.json"
# 後台設定 → 前台呈現的驅動關係
jq '.relations[]|select(.backend|test("X"))' "$KB/Definition_AOCCQA_relations.json"
# 跨系統資料流方向（Magento↔AOM↔EC）
jq '.relations[]|select(.feature=="X")' "$KB/Definition_AOCCQA_system_relations.json"
# 縮寫 / 錯誤訊息原文 / API 來源
jq '.acronyms,.error_messages,.apis' "$KB/Reference_AOCCQA_quicklookup.json"
```

限制：查詢只用於既有事實，不得用來回答尚未決定的產品決策。每次查詢記錄：查詢字串與回傳條目、來源/版本/owner/核准狀態、生效期間與適用範圍、是否對齊當前需求版本。未核准、過期、無出處、範圍不符的條目一律視為 `Reference Only`；查無或矛盾時，規則維持 `Missing`／`Ambiguous`／`Conflict`。名詞庫只解語意、不改授權——glossary 條目不能單獨建立新 Expected Behavior。

## Atomic rule model（原子規則模型）

每個「獨立變動的條件＋結果」建一條規則。國別/網站/角色/產品/狀態/設定/觸發/執行者/行為/排除/生效期/觀察點/來源 任一不同就拆。

每條含：`Rule ID` 與關聯 `Requirement ID`；規則維度；適用與排除範圍；條件/觸發；執行者/執行模式；預期行為與明確禁止行為；觀察點；生效期間；來源 ID；證據狀態；下游可用性。

保留字面值：欄位名、列舉值、國碼、產品型別、設定路徑、Job 名、排程時間、時區、API key、系統名。除非來源明確劃等號，下列一律保持區別：

- `null`、空字串、缺欄位、0、false、未回傳；
- 自動排程、手動執行、PM/RD 協助執行；
- 隱藏、停用、不支援、超出範圍、不適用；
- 軟刪除、硬刪除、停用、過期、封存；
- 資料未變、資料缺失、資料無效、處理失敗。

## Evidence status and usability（證據狀態與可用性）

每條規則指派**恰好一個**證據狀態：

| Evidence Status | 意義 |
|---|---|
| `Confirmed` | 明確、現行、已核准且內部一致 |
| `Derivable` | 由 Confirmed 規則直接組合，未產生新行為 |
| `Assumption Allowed` | 明確被允許的假設，附 owner 與標籤 |
| `Missing` | 必要規則或值缺失（→ 待補規則） |
| `Ambiguous` | 單一來源允許實質不同的解讀 |
| `Conflict` | 適用來源規定互斥行為 |
| `Out of Scope` | 明確排除於當前工作 |
| `Not Applicable` | 已確認不適用 |
| `Reference Only` | 歷史或實作證據，無授權力 |

> `Derivable` 可組合如 `Country=IT` 與 `Feature=Enabled` 等已確認事實；不得憑空發明 UI 該顯示什麼。

每條規則指派**恰好一個**下游可用性：`Usable`（範圍/條件/可觀察行為足以支撐 Pass/Fail）、`Partially Usable`（部分可用，須指出被卡部分）、`Blocked`（缺失/模糊/衝突/過期/不可取得，可能改變 Pass/Fail 或 setup）、`Excluded`（明確 Out of Scope 或 Not Applicable）。明確確認的禁止行為可用；沉默不等於禁止。

## Workflow（工作流）

1. **推導 Rule Loading Scope**：讀已確認 Requirement Matrix，只鎖會變動的維度（適用性、setup/測資可得性、動作/執行者/觸發/處理模式、預期或禁止行為、可觀察前台/後台/資料/整合結果）。不因出現在通用檢查表就擴張維度。
2. **建來源與權威登記**：盤點每個被允許來源，確立範圍與權威，標缺附件、過期版本、草稿狀態、不可取得。
3. **抽取並正規化原子規則**：拆複合規則、保留字面技術值、記錄明確別名、不確定等價標 `Ambiguous`。名詞/狀態值不明時依上節查 AOCCQA_glossary。
4. **解適用性**：每條指明在哪/對誰適用、何時/何觸發適用、由誰/什麼執行、結果在哪觀察、在哪明確排除、還有什麼未知。只有行為/條件/權威/生效期/觀察點全一致時才保留一條多市場規則；任一不同就拆。
5. **偵測缺口與矛盾**：有條件無行為；有行為卻缺範圍/觸發/執行者/模式/觀察點；國別/網站/角色/產品/狀態/設定/對映/時間覆蓋不完整；自動 vs 協助執行不明；只定成功路徑卻缺明確要求的失敗/無效路徑；UI/後台/API/Job/CSV/報表/Email/稽核/SFTP 定義互相矛盾；來源草稿/過期/不可取得/缺附件；修正是明確取代舊規則或只是衝突。**只提「答案會改變 Pass/Fail、適用性、test setup、所需外部協助、或能否觀察結果」的問題**，不給 PM 裝飾性問卷。
6. **準備決策導向釐清**：每題白話寫，附實際情境、競爭值、影響；依決策型別路由 owner；標優先級。不得自行回答，也不得把偏好選項當成已核准。

   | 決策型別 | 主要 owner |
   |---|---|
   | 預期產品行為、國別上線、商業資格、範圍 | PM |
   | API、對映、Job、log、狀態更新、觸發、實作合約 | RD |
   | 測試執行範圍、測資可得性、環境存取 | QA |
   | 跨 owner 決策 | PM + RD（敘明未解分工） |

   優先級：`P0` 卡核心行為或主 Pass/Fail；`P1` 卡重要市場/角色/狀態/資料/整合覆蓋；`P2` 限縮選配或低風險細節。
7. **判下游就緒度**：`Ready`（所有 in-scope 且 Pass/Fail 所需規則皆 Usable）／`Conditionally Ready`（只剩核准假設或孤立非核心缺口，須明說下游可用什麼）／`Not Ready`（有 Blocked 規則可能改變核心行為/setup/適用性/Expected Result）。就緒度針對 Rule Context，非 Test Case 品質。

## Output contract（輸出契約，依序回傳六段）

### 1. Rule Loading Summary

含 Requirement Matrix 版本、載入市場切片、是否需外部規則、收到與實際使用來源、各狀態計數、未解 P0/P1 數、下游就緒度。

### 2. Source and Authority Register

| Source ID | Source | Owner | Version/Date | Approval | Effective Period | Applicable Scope | Source Role | Accessibility |
|---|---|---|---|---|---|---|---|---|

### 3. Normalized Rule Context

| Rule ID | Requirement ID | Dimension | Applicable Scope | Excluded Scope | Condition/Trigger | Actor/Execution Mode | Expected Behavior | Prohibited Behavior | Observation Point | Effective Period | Source ID | Evidence Status | Downstream Usability |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

> 用穩定 ID 如 `RULE-001`。措辭釐清時保留原 Rule ID；商業語意改變時建新版本或新 ID。

### 4. Rule Applicability Matrix

| Rule ID | Country/Site | Role | Product/Data Type | State/Setting | Effective Period | Applicability | Evidence |
|---|---|---|---|---|---|---|---|

> Applicability 只用 `Applicable`／`Not Applicable`／`Out of Scope`／`Missing`／`Conflict`。**絕不把 `Missing` 轉成 `Not Applicable`。**

### 5. Missing and Conflict Rule Register（待補／衝突規則登記）

| Issue ID | Rule/Requirement ID | Type | Affected Scope | Missing or Competing Values | Source Evidence | Impact | Owner | Priority | Clarification Question |
|---|---|---|---|---|---|---|---|---|---|

> 用穩定 ID 如 `RULE-ISSUE-001`。只有「同一決策解同一規則缺口、同一 owner、同一範圍」時才合併問題。

### 6. Downstream Readiness

敘明整體就緒度、Usable Rule IDs、Blocked Rule IDs、Excluded Rule IDs、被允許假設、准許下游範圍、禁止下游範圍、下一個需要的人工決策。

## Completion criteria（完成準則）

下列全部成立才可宣稱完成：

- Requirement Matrix 已過執行閘門；
- 只載相關規則與來源（按市場切片，未載全部國別）；
- 每條原子規則可追溯至 Requirement ID 與（可得時）Source ID；
- 字面技術值與有意義區別皆保留；
- 每條規則各一個證據狀態與一個下游可用性；
- 適用性、排除、生效期、未知彼此分明；
- 每個缺失/模糊/過期/不可取得/衝突的規則都可見（待補規則已列出）；
- 沒有規則繼承自其他市場、專案、Test Case 或最佳實務；
- 沒有產生任何 Coverage Gap 或 Test Case 內容。
