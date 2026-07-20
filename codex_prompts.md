# Codex 修改提示词 — 工业多通道示波记录软件

> 以下提示词按修复顺序排列，**请按顺序逐一交付给 Codex**，每完成一个再交下一个。
> 每个提示词都完整描述了「问题现象 → 根因分析 → 修改要求 → 参考文件」，不需要 Codex 自行猜测。

---

## 提示词 1：修复更新模式曲线不显示的核心 Bug

### 问题现象

1. 在「更新模式」下点击「开始模拟」，波形区域没有任何曲线出现。
2. 点击「左移」按钮后，曲线突然出现。
3. 在更新模式下点击「位置复位」后，曲线再次消失。
4. 切换到「滚动模式」，即使不点击左移，曲线也能正常显示。

### 根因分析

`WaveformPanel.qml` 中 `rebuildFrame()` 的触发逻辑存在时序依赖缺陷：

```qml
function rebuildFrame() {
    if (activePage && displayMode === "update" && !reviewingHistory && waveformCanvas.width > 0)
        channelStore.buildUpdateFrames(...)
}
```

`rebuildFrame()` 只依赖 `onLatestSampleTimeChanged`、`onHistoryOffsetSecondsChanged`、`onTimePerDivMsChanged`、`onDisplayModeChanged`、`onActivePageChanged` 这几个信号触发。但当模拟刚开始时：

1. `startSimulation()` 先调用 `appendSimulationSamples(100)` 写入首批数据，这会改变 `latestSampleTime`。
2. **此时 `simulationRunning` 还未设为 `true`**（代码顺序是先追加数据，后设置 `simulationRunning = true`）。
3. `latestSampleTimeChanged` 触发 → `rebuildFrame()` 被调用 → `buildUpdateFrames()` 生成更新帧 → Canvas 应该绘制。
4. 但问题在于：`buildUpdateFrames()` 内部调用了 `channelModel.setProperty(index, "updateFrame", frame)`，这会触发 `frameRevision` 改变，导致 `onFrameRevisionChanged` → `schedulePaint()`。
5. 而 **`schedulePaint()` 使用了一个 33ms 的 `paintTimer`**，该 timer 设置了 `repeat: false`，且逻辑是 `if (!paintTimer.running) paintTimer.start()`。
6. 多个信号几乎同时触发时，第一个信号启动了 `paintTimer`，后续信号因为 `paintTimer.running === true` 被跳过。
7. 但更根本的问题可能是：**Canvas 的 `onPaint` 回调执行时，`requestPaint()` 是异步的**。当首批数据写入后立即调用 `requestPaint()`，Qt 的渲染循环可能还没有准备好处理这次绘制请求，或者绘制时 `updateFrame` 数组还没有被正确地「可见」到 Canvas 的 paint 上下文中。

**次要根因**：在 `Main.qml` 的 `startSimulation()` 中，首次启动时调用 `appendSimulationSamples(100)` 生成了 100 个样本（约 20ms 数据），但在 `timePerDivMs = 1.0`（默认）下，`visibleTimeSeconds = 0.01s`，只有 10ms 的可见窗口。100 个样本足够覆盖这个窗口。所以数据量不是问题。

**核心根因**：`WaveformPanel.qml` 的绘制路径中，更新模式的绘制分支依赖 `data.updateFrame`，但该帧是在 `rebuildFrame()` 中通过 `channelStore.buildUpdateFrames()` 异步写入的。Canvas `onPaint` 执行时，`updateFrame` 可能尚未正确绑定到 paint 上下文中，导致绘制时 `frame` 为空或 `frame.length === 0`。

当点击「左移」时，`historyOffsetSeconds` 改变 → `onHistoryOffsetSecondsChanged` → `rebuildFrame()` + `schedulePaint()` → **此时因为触发链路不同**，绘制能够成功。

### 修改要求

**A. 修改 `WaveformPanel.qml` 的 `rebuildFrame()` 逻辑：**

1. **去掉 `rebuildFrame()` 中的条件限制**，改为无条件生成更新帧：
```qml
function rebuildFrame() {
    if (activePage && displayMode === "update" && !reviewingHistory) {
        if (waveformCanvas.width > 0) {
            channelStore.buildUpdateFrames(
                latestSampleTime,
                visibleTimeSeconds,
                Math.max(1024, Math.min(4096, Math.round(waveformCanvas.width * 2)))
            )
        }
    }
}
```

2. **增强 `onPaint` 中的更新帧绘制逻辑**，增加防御性检查：
```javascript
if(!root.usesHistory && data.enabled) {
    const frame = data.updateFrame
    if (frame && frame.length > 1) {
        for(let i = 0; i < frame.length; ++i) {
            point(frame[i], i / (frame.length - 1) * w)
        }
    }
}
```

**B. 修改 `Main.qml` 的 `startSimulation()`：**

将 `simulationRunning = true` 的赋值提前到调用 `appendSimulationSamples()` 之前，确保 Timer 先启动，再写入首批数据：

```qml
function startSimulation() {
    if (!simulationRunning) {
        simulationRunning = true
        if (!channelStore.hasData) {
            appendSimulationSamples(100)
        }
        appendLog("Four-channel simulation started")
    }
}
```

**C. 在 `WaveformPanel.qml` 中添加一个「首次启动强制重绘」机制：**

在 `simulationRunning` 属性变化时，如果变为 `true` 且处于更新模式，强制重建帧并立即请求重绘：

```qml
onSimulationRunningChanged: {
    if (simulationRunning && displayMode === "update") {
        rebuildFrame()
        waveformCanvas.requestPaint()
    }
}
```

**D. 修改 `schedulePaint()` 移除 timer 去重逻辑：**

```qml
function schedulePaint() {
    if (activePage) {
        paintTimer.restart()  // 用 restart() 替代条件检查
    }
}
```

或者直接调用 `waveformCanvas.requestPaint()`，绕过 timer：

```qml
function schedulePaint() {
    if (activePage) {
        waveformCanvas.requestPaint()
    }
}
```

> **注意**：去掉 33ms paintTimer 后，需要确保不会过度绘制。可以在 `onPaint` 中做限频，或者在 `schedulePaint` 中用节流（throttle）替代去重（debounce）。

### 涉及的文件

- `WaveformPanel.qml` — 修改 `rebuildFrame()`、`schedulePaint()`、`onPaint`、添加 `onSimulationRunningChanged`
- `Main.qml` — 修改 `startSimulation()` 中 `simulationRunning` 的赋值顺序

---

## 提示词 2：右侧面板重构 — 显示通道与当前通道合并为多选下拉框

### 问题现象

右侧「通道参数」面板当前分为两个独立区域：
- **上部**：「显示通道」区 — CH1~CH4 四个按钮，点击切换 `visible` 状态
- **下部**：「当前通道」区 — 一个 `ComboBox` 下拉框，选择当前编辑通道

用户期望：这两个功能应该**合并为一个「通道多选下拉框」**，行为如下：
- 下拉框中列出所有通道，每项带**复选框**，勾选 = 加入波形显示（`visible = true`），取消勾选 = 从波形中移除（`visible = false`）
- **最后一次勾选的通道**（或**点击波形上方图例标签**选中的通道）就是**当前参数编辑通道**（`selectedChannelIndex`）

### 设计参考

参考常见的多通道示波器软件（如 PicoScope、Saleae Logic）的通道选择模式：
- 一个紧凑的通道列表，每项有颜色标记 + 名称 + 复选框
- 点击通道名称或颜色标记本身切换当前编辑通道
- 复选框控制是否在波形中显示

### 修改要求

**A. 移除 `ParameterPanel.qml` 中旧的「显示通道」按钮区和「当前通道」下拉框。**

**B. 在相同位置创建一个新的「通道选择列表」，使用 `ListView` 或 `ColumnLayout` 实现：**

每个通道一行，包含：
1. 一个**颜色指示块**（小矩形，填充通道颜色）
2. 一个**复选框**（`CheckBox` 或自定义勾选框），绑定到 `channel.visible`
3. 通道**名称文本**（点击此处切换当前通道）
4. 通道**状态标签**（「已启用」绿色 /「已停用」黄色）

整体设计风格保持深色工业风，与现有 UI 一致。

**C. 行为逻辑：**

1. 勾选复选框 → `toggleChannelVisible(index)` → 设置 `channel.visible = true` → 同时将当前通道设为该通道
2. 取消勾选复选框 → `toggleChannelVisible(index)` → 设置 `channel.visible = false` → 如果当前选中的就是该通道，则自动切换到第一个仍然可见的通道（如有）
3. 点击通道名称（而非复选框）→ 仅切换 `selectedChannelIndex`，不改变 `visible`
4. 当所有通道都被取消勾选时，`selectedChannelIndex` 保持不变（保留最后一个选中的通道索引）
5. 波形上方图例标签的点击行为保持不变：点击图例标签切换 `selectedChannelIndex`

**D. 更新信号连接：**

确保 `ParameterPanel.qml` 的 `toggleChannelRequested` 和 `selectedChannelRequested` 信号仍然正确连接到 `Main.qml` 的处理函数。可能需要新增信号或修改现有信号的触发逻辑。

### 涉及的文件

- `ParameterPanel.qml` — 重构右侧面板，移除「显示通道」按钮和「当前通道」下拉框，创建新的多选通道列表
- `Main.qml` — 可能需要微调信号处理逻辑（`toggleChannelVisible` 和 `setSelectedChannel` 的逻辑基本不变）

---

## 提示词 3：美化中间波形区域 UI

### 问题现象

当前中间波形区域（`WaveformPanel.qml`）的视觉效果比较简陋，需要改进以符合工业级示波器软件的品质感。

### 修改要求

**A. 顶部标题栏美化：**

当前标题栏只是一个简单的 `Label` + 状态文字。改为：
1. 添加一个半透明深色背景条（`Rectangle`），与左侧导航栏和右侧参数面板风格统一
2. 标题「四通道实时波形」使用更大的字号（20px），左侧加一个波形小图标（可用 Unicode 字符或 Canvas 绘制）
3. 状态文字（「模拟采集中·更新模式」等）使用彩色标签样式，带圆角背景

**B. 图例区域美化：**

当前图例是横排按钮，改为：
1. 每个通道图例用圆角卡片样式，带 4px 左边界颜色条（通道颜色）
2. 卡片内显示：通道名称（加粗）+ 量程值 + 状态标记（已停用/已隐藏）
3. 选中通道的卡片有发光边框效果
4. 图例区域整体背景加深

**C. 波形 Canvas 区域优化：**

1. 网格线颜色微调：主网格线（粗线）使用 `#1a3d52`，次网格线（细线）使用 `#0e2533`
2. 零电平线使用更明显的样式：`#2a6b85`，虚线长度加大
3. 添加刻度标签的边距和内阴影效果
4. 波形曲线的 `lineWidth` 从 2 改为 1.5，更精细
5. 添加简单的坐标轴刻度标签（顶部和右侧的时间/电压标签）

**D. 底部操作按钮美化：**

1. 按钮使用统一的高度（36px），带圆角（6px）
2. 「开始模拟」使用绿色系（`#168b7c`），「停止模拟」使用红色系（`#a1514d`）
3. 普通操作按钮使用蓝灰色系（`#285b73`、`#354452`）
4. 「清除历史」使用暗红色（`#493b3a`）
5. 按钮悬浮效果：`hovered` 时颜色变亮 20%
6. 按钮分割线或间距调整，使其视觉分组更清晰：左边三个为一组（开始/停止/适配），右边「清除历史」单独一组

### 涉及的文件

- `WaveformPanel.qml` — 全面美化

---

## 提示词 4：功能分离 — 将参数面板的通道控制与波形控制分离

### 问题现象

Codex 将「通道控制」（显示通道、当前通道选择）和「波形控制」（时基、量程、偏移等）都塞在右侧同一个 `ParameterPanel` 中，导致右侧面板功能混杂。

### 修改要求

**将右侧面板拆分为两个独立的逻辑区域，但仍放在同一个 `ParameterPanel.qml` 中（或拆分为两个独立的 QML 组件）：**

**区域 1 — 通道选择区（顶部）**
- 只包含新的多选通道列表（已在提示词 2 中重构）
- 每个通道的状态概览（启用/停用、可见/隐藏）
- 每个通道的基本控制（启用/停用按钮）

**区域 2 — 参数编辑区（中下部）**
- 只针对当前选中的通道
- 垂直控制：量程（V/div）、垂直偏移（上移/下移/归零）
- 水平控制：时基（ms/div）、历史位置（左移/右移/归零）
- 显示控制：更新/滚动模式、栅格开关

**两个区域之间使用更明显的分隔线（`Separator`）分开，分隔线颜色使用 `#2a4253`。**

### 涉及的文件

- `ParameterPanel.qml` — 重新组织布局结构

---

## 提示词 5：修复模拟数据链路 — 确保更新模式与滚动模式的绘制一致性

### 问题现象

综合所有 Bug，核心问题是「更新模式」和「滚动模式」的绘制路径存在不一致性：
- 滚动模式：直接从 `historyBuffer` 读取数据绘制，数据路径可靠
- 更新模式：依赖 `buildUpdateFrames()` 生成的独立帧数组，存在时序和同步问题

### 根因分析

两个模式使用了完全不同的数据源：
1. **滚动模式**：Canvas 直接从 `channelStore` 的历史环形缓冲中读取样本 → 绘制 → 数据始终存在，不会丢失
2. **更新模式**：先调用 `buildUpdateFrames()` 生成一个独立的高分辨率帧数组 → 存入 `updateFrame` 属性 → Canvas 读取该数组绘制。这个路径有一系列触发依赖，任何一个环节断掉就会导致无曲线

### 修改要求

**统一两个模式的数据路径，降低耦合度：**

**方案 A（推荐，改动最小）：让更新模式也使用历史缓冲绘制（当历史中有足够数据时）**

修改 `WaveformPanel.qml` 的 `onPaint` 逻辑：

```javascript
// 在绘制循环中：
if (data.visible) {
    c.strokeStyle = data.color
    c.lineWidth = 1.5
    c.beginPath()
    let drew = false
    
    if (displayMode === "update" && !reviewingHistory && data.enabled) {
        // 更新模式：如果有 updateFrame 且长度 > 0，用 updateFrame
        // 否则回退到历史缓冲
        const frame = data.updateFrame
        if (frame && frame.length > 1) {
            for (let i = 0; i < frame.length; ++i) {
                // ...绘制 updateFrame
            }
        } else if (hasHistoryData) {
            // 回退到历史缓冲绘制（同滚动模式逻辑）
            // ...
        }
    } else {
        // 滚动模式或历史回看：从历史缓冲绘制
        // ...
    }
    
    if (drew) c.stroke()
}
```

**方案 B（更彻底）：更新模式也改为使用历史缓冲绘制**

更新模式不再使用独立的 `updateFrame`，而是直接从历史缓冲中采样绘制点，采样策略采用均匀降采样（保持与滚动模式一致）。

这样两个模式共用同一套数据 + 同一套绘制逻辑，唯一的区别是：
- **更新模式**：`followLatest = true` 且 `displayMode === "update"` 时，每帧从最新时间窗口采样固定数量的点（高分辨率、重新计算）
- **滚动模式**：从历史缓冲中取可见窗口的样本，实时跟随

### 涉及的文件

- `WaveformPanel.qml` — 修改 `onPaint` 逻辑
- `ChannelStore.qml` — 可能不需要修改（历史缓冲数据已经完备）
- `Main.qml` — 不需要修改

---

## 附：当前代码结构参考

### 文件职责

| 文件 | 职责 |
|---|---|
| `Main.qml` | 主窗口、全局状态持有者、日志、模拟 Timer、页面切换 |
| `ChannelStore.qml` | 四通道数据模型、历史环形缓冲、模拟信号生成 |
| `WaveformPanel.qml` | 波形 Canvas 绘制、启停按钮、图例、历史导航 |
| `ParameterPanel.qml` | 右侧通道参数面板（需要重构） |
| `NavigationPanel.qml` | 左侧功能导航 |
| `ChannelSettingsPage.qml` | 通道设置页面（通道名、启用、显示、颜色） |
| `AcquisitionSettingsPage.qml` | 采集设置占位页 |
| `RecordingPage.qml` | 录制设置占位页 |
| `SystemStatusPage.qml` | 系统状态页面 |

### 关键状态传递关系

```
Main.qml (唯一状态持有者)
  ├── channelStore (ChannelStore.qml — 数据模型)
  ├── selectedChannelIndex (当前编辑通道)
  ├── simulationRunning (模拟运行状态)
  ├── displayMode ("update" | "roll")
  ├── timePerDivMs (时基)
  ├── historyOffsetSeconds (历史偏移)
  ├── followLatest (是否实时跟随)
  │
  ├── WaveformPanel.qml (接收上述状态，通过信号请求操作)
  │   └── Canvas onPaint (绘制波形)
  │
  └── ParameterPanel.qml (接收上述状态，通过信号请求修改)
      └── 当前包含：显示通道按钮 + 当前通道下拉框 + 参数编辑
```

### 关键属性默认值

| 属性 | 默认值 | 说明 |
|---|---|---|
| `timePerDivMs` | 1.0 | ms/格 |
| `simulationSampleRate` | 5000 | 模拟采样率 5 kSa/s |
| `historyCapacity` | 100000 | 环形缓冲容量（约 20s） |
| `selectedChannelIndex` | 0 | 默认选中 CH1 |
| `displayMode` | "update" | 默认更新模式 |
| `followLatest` | true | 默认实时跟随 |
| `gridVisible` | true | 默认显示栅格 |
| CH1 `visible` | true | 仅 CH1 默认可见 |
| CH1 `verticalOffsetV` | 1.5 | CH1 默认垂直偏移 |
