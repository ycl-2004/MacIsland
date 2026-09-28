<h1 align="center">Atoll</h1>

<p align="center">
  <strong>專為開發者與 AI Agent 工作流打造的 macOS 瀏海中控台。</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/build-1.0.0%20(YC__Island__v1)-111111" alt="版本：1.0.0 (YC_Island_v1)">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-111111?logo=apple&logoColor=white" alt="支援 macOS 14.0 以上">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&logoColor=white" alt="以 SwiftUI 與 AppKit 打造">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-111111" alt="GPL-3.0 授權條款"></a>
</p>

<p align="center">
  <a href="#快速開始">快速開始</a>
  ·
  <a href="#為什麼選擇-atoll">為什麼選擇 Atoll</a>
  ·
  <a href="#功能特點">功能特點</a>
  ·
  <a href="#運作原理">運作原理</a>
  ·
  <a href="#隱私與安全">隱私與安全</a>
  ·
  <a href="#原始碼建置">原始碼建置</a>
  ·
  <a href="#致敬與致謝">致敬與致謝</a>
  ·
  <a href="LICENSE">授權條款</a>
  ·
  <a href="ReadMe.md">English</a>
</p>

Atoll 將 MacBook 螢幕頂部的瀏海區域轉化為低干擾、可隨時互動的指揮中控台。在專注工作時完全隱形，當游標靠近、觸控板滑動或按下全域快捷鍵時，便以順暢的原生 SwiftUI 動畫優雅展開。

本版本為 YC 針對個人日常開發與 AI 協作工作流深度定制的私有版本（`YC_Island_v1`）。它首度將 **Claude Code**、**Codex** 與 **Antigravity** 等 AI Coding Agent 的運行狀態與終端即時流式輸出深度整合至硬體瀏海，同時剔除冗餘的後台常駐進程，並打磨了多音源媒體控制、動態掃光歌詞、鎖定畫面小組件、互動式標尺計時器與低耗能硬體監控等日常核心工具。

> **源碼優先的個人版本。** 本儲存庫為 YC 個人在 Apple Silicon MacBook 上使用的日常版本，未發布預編譯簽名安裝包，建議直接透過 Xcode 建置與執行。本專案基於 [Atoll by Ebullioscopic](https://github.com/Ebullioscopic/Atoll) 與 [boring.notch](https://github.com/TheBoredTeam/boring.notch) 衍生開發，並遵循 GNU 通用公共授權條款第三版（GPL-3.0）。

---

## 快速開始

1. **複製本儲存庫：**
   ```bash
   git clone https://github.com/ycl-2004/Atoll.git
   cd Atoll
   ```
2. **在 Xcode 中開啟專案：**
   ```bash
   open DynamicIsland.xcodeproj
   ```
3. 將執行目標設定為 **My Mac**，並按下 **⌘R** 進行編譯與啟動。
4. **初次啟動時授予必要權限：**
   - **輔助使用 (Accessibility)**：用於在多螢幕與桌面空間精確定位瀏海覆蓋視窗，並監聽全域快捷鍵。
   - **螢幕錄製 (Screen Recording)**：僅用於「圈選螢幕提問」區域截圖及螢幕取色器放大鏡。
   - **音樂 (Music)**：用於存取 Apple Music 播放狀態、曲目中繼資料與控制指令。
5. 將游標移至螢幕頂部瀏海即可展開面板，或隨時按下 `⌘⇧A` 框選螢幕任意區域直接向 AI Agent 提問。

### 系統需求

- **作業系統**：macOS 14.0 (Sonoma) 或 macOS 15+ (Sequoia)。
- **硬體設備**：配備實體螢幕瀏海的 Apple Silicon MacBook（14 吋 / 16 吋 MacBook Pro、M2/M3 MacBook Air 各世代機種）。
- **開發工具**：Xcode 15.0 以上版本（附帶 Swift 5.9 以上工具鏈）。

---

## 為什麼選擇 Atoll

- **置於硬體頂部的 AI Agent 駕駛艙。** 無需在多個終端分頁間反覆切換確認進度，Claude Code、Codex 與 Antigravity 的即時工作階段會直接呈現在螢幕頂部瀏海，提供即時狀態指示、流式文字輸出與回覆控制。
- **即時圈選提問 (Ask About Screen)。** 按下 `⌘⇧A` 拖曳框選螢幕上的任何視窗、程式碼或介面 Bug，截圖與問題即刻注入當前活躍的 Agent 會話，無需手動截圖、存檔或切換視窗。
- **剔除臃腫，安靜省電。** 移除不常用的剪貼簿歷史管理器、內建 Web 終端模擬器、孤立的 AppleScript 腳本與常駐防止休眠守護進程，維持極低的待機 CPU 與記憶體佔用。
- **精雕細琢的日常實用工具。** 完美支援 Apple Music、Spotify、TIDAL、YouTube Music、Cider 與網易云音樂；動態逐字掃光歌詞；鎖定畫面小組件；互動式滾動標尺計時器；以及極低開銷的 SMC 晶片硬體監控。
- **純本機隱私保護。** 所有 Agent 通訊、終端會話與截圖提問均透過本機 IPC 與檔案監聽完成。無任何帳號系統、無使用遙測數據、無第三方中間伺服器。

---

## 功能特點

### 🤖 AI Coding Agent 即時駕駛艙
- **即時工作階段卡片**：在瀏海面板專屬分頁中集中監控 **Claude Code**、**Codex** 與 **Antigravity** 的活躍進程。
- **瀏海動態指示 (Live Activity)**：當背景 Agent 正在思考、執行終端指令或生成程式碼時，頂部瀏海會顯示低調流暢的動態光點與狀態。
- **終端即時會話抽屜**：直接在瀏海展開面板中閱讀 Agent 的即時流式輸出，並直接輸入追加指令或回應。
- **圈選螢幕提問 (`⌘⇧A`)**：隨時框選畫面任意區域，將局部影像與自訂 Prompt 直接派發給選定的 Agent 處理。

### 🎵 媒體與音訊 HUD
- **多播放器全面整合**：原生支援 Apple Music、Spotify、TIDAL、YouTube Music、Cider 以及網易云音樂（NetEase Cloud Music）。
- **即時音訊頻譜波形**：透過 C++ CoreAudio 程序監聽實現硬體加速的低延遲即時跳動頻譜。
- **動態掃光歌詞**：支援 LRC 時間軸的動態平滑掃光歌詞，鎖定畫面上亦提供展開式大字版即時歌詞。
- **觸控板滑動手勢**：在瀏海區域以雙指水平滑動即可快進/快退 10 秒或切換曲目，附帶原生觸覺震動回饋。

### 🔒 鎖定畫面組件與系統 HUD
- **鎖定畫面播放器**：展示高解析度專輯封面、即時進度條、獨立音量滑桿與側邊即時歌詞欄。
- **模組化鎖定畫面組件**：提供倒數計時器、基於 Open-Meteo 的本機即時天氣、電池充電百分比與已連線藍牙設備電量。
- **瀏海系統 HUD 替代方案**：以頂部俐落的原生動畫替代系統預設的大方塊 HUD，涵蓋音量、螢幕亮度、鍵盤背光、網路離線、鏡頭/麥克風隱私與螢幕錄製提示。

### ⚡ 系統監控與開發者工具
- **硬體效能遙測**：低負載 SMC 與 IOReport 感測器即時監測各核心 CPU 負載與溫度、GPU 使用率、統一記憶體壓力、網路傳輸速率與磁碟 I/O。
- **互動式標尺計時器**：仿實體滾動標尺的番茄鐘與倒數工具，並與鎖定畫面計時器保持同步。
- **螢幕取色器**：具備 10 倍像素級放大鏡與 HEX 色碼一鍵複製功能。
- **檔案暫存架 (Shelf)**：支援拖曳暫存檔案與素材，亦可由終端機快速加入（`open -a Atoll /path/to/file`）。
- **行事曆速覽**：快速檢視即將到來的日程活動。

---

## 運作原理

- **瀏海幾何佈局與游標捕捉**：Atoll 透過視窗管理 API 監聽螢幕頂端邊界區域的游標懸停與手勢動作，在不奪取當前使用中視窗焦點的前提下平滑展開與收折 SwiftUI 畫布。
- **本機 Agent 觀察機制**：透過 `AgentBridge` 與 `AgentSessionStore` 監聽 Claude Code、Codex 與 Antigravity 的本機記錄檔、輸出管道與 Language Server 端點，不經由外部伺服器即可直接解析流式更新。
- **螢幕提問管線**：`ScreenQuestionManager` 藉由 `CGWindowListCreateImage` 擷取使用者圈選的矩形區域，將其包裝為視覺上下文，並即時派送至對應 Agent 的會話管理服務。

---

## 隱私與安全

- **嚴格維持純本機運作**：不設任何登入帳號、不收集任何使用遙測資料、不安裝任何追蹤點或第三方崩潰報告模組。
- **Agent IPC 不出本機**：與 Claude Code、Codex 及 Antigravity 的所有互動均透過本機進程通訊及檔案完成，絕不將您的程式碼、對話或提示詞傳送至第三方中間伺服器。
- **明確的網路存取邊界**：僅在使用者啟用特定功能時發起最小化外網請求：使用 Open-Meteo 獲取當地天氣預報，以及在音樂播放時向公開歌詞 API（LRCLIB / 網易云音樂）請求歌詞。
- **螢幕錄製存取範疇**：螢幕截圖僅在使用「圈選螢幕提問」或「取色器放大鏡」時觸發單次截圖，Atoll 絕不會在背景持續錄製或上傳您的螢幕畫面。

---

## 常見問題 (FAQ)

<details>
<summary>為什麼 Atoll 需要輔助使用與螢幕錄製權限？</summary>

**輔助使用 (Accessibility)** 權限是用於在所有虛擬桌面與空間頂部正確定位瀏海懸浮視窗、感應螢幕凹口附近的游標懸停，以及註冊全域快捷鍵。

**螢幕錄製 (Screen Recording)** 權限則嚴格僅在使用者主動觸發功能時運作：包括使用「圈選提問 (`⌘⇧A`)」時擷取選定矩形，以及在螢幕取色器中放大游標所在像素。Atoll 絕不會在背景進行畫面錄製或儲存任何螢幕歷史。

</details>

<details>
<summary>「圈選提問」如何與我的終端 Agent 進行連接？</summary>

當您在畫面上拉出選取框時，Atoll 會擷取該區域畫面並與您的提問整合，接著透過本機 IPC 端點與當前正在執行的 Claude Code、Codex 或 Antigravity 終端會話建立連線，將影像與文字直接送達 Agent 的上下文輸入端。

</details>

<details>
<summary>支援哪些音樂播放器？</summary>

Atoll 支援 Apple Music、Spotify、TIDAL、YouTube Music、Cider 以及網易云音樂。Now Playing 中繼資料將自動更新，而播放控制指令（播放/暫停、換曲、進度滑動、喜愛歌曲）均走各播放器的原生 AppleScript 介面或本機 API。

</details>

<details>
<summary>如何完全解除安裝 Atoll 並清除設定？</summary>

請從選單列或瀏海設定中結束 Atoll，並將 `/Applications/Atoll.app` 移至垃圾桶。若欲清除所有偏好設定，請在終端機執行：

```bash
defaults delete com.ebullioscopic.DynamicIsland
```

隨後可在 **系統設定 → 隱私權與安全性 → 輔助使用 / 螢幕錄製** 中撤銷相關權限。

</details>

---

## 原始碼建置

<details>
<summary>系統需求、建置指令與測試驗證</summary>

### 需求條件
- macOS 14.0 以上版本。
- Xcode 15.0 以上版本。
- 配備實體瀏海的 Apple Silicon Mac。

### 命令列建置驗證
若要在不配置開發者簽名證書的情形下驗證建置：

```bash
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

### 執行單元測試
執行單元測試套件：

```bash
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:DynamicIslandTests
```

本專案儲存庫完整追蹤原始碼、素材目錄、測試組件與共享 Xcode 專案結構，同時嚴格忽略自動生成的 DerivedData、本機快取與開發者 Team ID。

</details>

---

## 專案結構

| 目錄 / 檔案 | 職責說明 |
| :--- | :--- |
| `DynamicIsland/` | 應用程式核心原始碼、AppKit 視窗控制器與 SwiftUI 介面 |
| `DynamicIsland/components/Agents/` | AI Agent 工作階段卡片、即時流式檢視器與螢幕提問卡片 |
| `DynamicIsland/managers/Agents/` | Agent 工作階段註冊表、記錄解析器與本機 IPC 通訊橋樑 |
| `DynamicIsland/components/LockScreen/` | 鎖定畫面小組件（音樂播放器、天氣、計時器、藍牙電量） |
| `DynamicIsland/components/Music/` | 音樂播放器整合、歌詞同步引擎與頻譜視覺化組件 |
| `DynamicIsland/components/Notch/` | 瀏海視窗容器、導覽分頁、頂部標題列與展開動畫 |
| `DynamicIsland/components/Settings/` | 偏好設定面板、佈局開關與快捷鍵錄製器 |
| `DynamicIsland/components/Shelf/` | 拖曳暫存檔案架 |
| `DynamicIsland/components/Stats/` | SMC 與 IOReport 硬體效能感測讀取器 |
| `DynamicIsland/components/Timer/` | 互動式滾動標尺計時器與倒數邏輯 |
| `DynamicIslandTests/` | 狀態管理器、歌詞解析與會話處理單元測試 |
| `DynamicIslandUITests/` | 介面自動化測試套件 |
| `tests/` | 獨立回歸測試腳本與驗證輔助工具 |

---

## 版本管理

- **版本名稱 (Release Name)**：`YC_Island_v1`（定義於 `DynamicIsland/strings/constants.swift`）。
- **行銷版本 (Marketing Version)**：`1.0.0` (組建編號 1637，位於 `DynamicIsland.xcodeproj`）。
- **主要分支**：`feat/agents`。
- 本專案採源碼優先管理，版本號標示個人工作流客製化的演進里程碑。

---

## 致敬與致謝 (Credits & Homage)

Atoll（YC 客製版）以無比感激的心情，向奠定技術基石的優秀開源前輩專案致敬：

- [**Atoll**](https://github.com/Ebullioscopic/Atoll) 由 **Ebullioscopic** 開發 — 現代且高度可客製化的 macOS 瀏海中控台基底。
- [**Boring.Notch**](https://github.com/TheBoredTeam/boring.notch) 由 **TheBoredTeam** 開發 — 原創開創 macOS 動態島概念與核心互動模式的先驅專案。
- [**Stats**](https://github.com/exelban/stats) 由 **exelban** 開發 — 紮實健壯的 SMC 與 IOReport 硬體感測器讀取架構。
- [**Alcove**](https://tryalcove.com) — 鎖定畫面組件版面配置的概念啟發。
- [**Open-Meteo**](https://open-meteo.com) — 免費且注重隱私的開放氣象 API。
- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) 由 **Lakr233** 開發 — 鎖定畫面視窗繪製與穿透核心技術。
- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio) — 高效能即時音訊波形取樣實作。
- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) — 電池充電 HUD 視覺設計靈感。

---

## 已知限制

- **需配備實體螢幕瀏海**：視窗幾何形狀與游標碰撞偵測均針對 Apple Silicon MacBook 實體螢幕凹口（14 吋 / 16 吋 MBP、M2/M3 MacBook Air）進行深度校準。
- **支援的 Agent 環境邊界**：目前即時連線僅支援 Claude Code、Codex 與 Antigravity，其他 CLI 工具需自行擴充適配器。
- **初次授權要求**：首次使用「圈選提問」時，需在 macOS 系統設定中核准螢幕錄製權限並重新啟動應用程式。

---

## 授權條款

Atoll 為遵循 [GNU 通用公共授權條款第三版 (GPL-3.0)](LICENSE) 的自由軟體。

有關素材授權與第三方商標說明，請參閱 [NOTICE](NOTICE)、[COPYRIGHT_ASSETS](COPYRIGHT_ASSETS) 與 [TRADEMARKS](TRADEMARKS)。
