import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#132633"
    border.color: "#314b5b"
    required property bool activePage
    required property var channelStore
    required property int selectedChannelIndex
    required property bool simulationRunning
    required property string displayMode
    required property bool gridVisible
    required property real timePerDivMs
    required property real latestSampleTime
    required property real historyOffsetSeconds
    required property real samplePeriodSeconds
    signal selectedChannelRequested(int index)
    signal startRequested(); signal stopRequested(); signal verticalFitRequested(); signal resetPositionsRequested(); signal clearHistoryRequested()
    readonly property real visibleTimeSeconds: timePerDivMs * 10 / 1000
    readonly property bool reviewingHistory: historyOffsetSeconds > 1e-9
    readonly property bool usesHistory: reviewingHistory || displayMode === "roll"
    function formatNumber(v) { return Number(v).toFixed(1).replace(/\.0$/, "") }
    function formatTime(v) { return Math.abs(v) < 1 ? formatNumber(v * 1000) + " ms" : formatNumber(v) + " s" }
    function schedulePaint() { if (activePage && waveformCanvas.width > 0 && waveformCanvas.height > 0) waveformCanvas.requestPaint() }
    function rebuildFrame() { if (displayMode === "update" && !reviewingHistory && waveformCanvas.width > 0) channelStore.buildUpdateFrames(latestSampleTime, visibleTimeSeconds, Math.max(1024, Math.min(4096, Math.round(waveformCanvas.width * 2)))) }
    onLatestSampleTimeChanged: { rebuildFrame(); schedulePaint() }
    onHistoryOffsetSecondsChanged: { rebuildFrame(); schedulePaint() }
    onTimePerDivMsChanged: { rebuildFrame(); schedulePaint() }
    onDisplayModeChanged: { rebuildFrame(); schedulePaint() }
    onGridVisibleChanged: schedulePaint()
    onSelectedChannelIndexChanged: schedulePaint()
    onSimulationRunningChanged: { rebuildFrame(); schedulePaint() }
    onActivePageChanged: { if (activePage) { rebuildFrame(); schedulePaint() } }
    Connections { target: root.channelStore; function onSampleRevisionChanged() { root.rebuildFrame(); root.schedulePaint() } function onFrameRevisionChanged() { root.schedulePaint() } function onRevisionChanged() { root.schedulePaint() } }
    component ActionButton: Button { id: b; property color fillColor: "#223542"; implicitHeight: 32; contentItem: Text { text: b.text; color: b.enabled ? "#d9e4ec" : "#71818d"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } background: Rectangle { radius: 4; color: b.enabled ? b.fillColor : "#29333a" } }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10
        RowLayout { Layout.fillWidth: true; Label { text: qsTr("四通道实时波形"); color: "#d9e4ec"; font.pixelSize: 17; font.bold: true } Item { Layout.fillWidth: true } Label { text: root.reviewingHistory ? qsTr("历史回看：距最新 ") + root.formatTime(root.historyOffsetSeconds) : (root.simulationRunning ? (root.displayMode === "update" ? qsTr("模拟采集中 · 更新模式") : qsTr("模拟采集中 · 滚动模式")) : qsTr("模拟采集已停止")); color: root.reviewingHistory ? "#e8a94b" : "#35d19b" } }
        Flickable { Layout.fillWidth: true; Layout.preferredHeight: 30; contentWidth: legendRow.width; contentHeight: height; clip: true; interactive: contentWidth > width; boundsBehavior: Flickable.StopAtBounds
            Row { id: legendRow; width: implicitWidth; height: parent.height; spacing: 8
            Repeater { model: root.channelStore.channelModel; delegate: Button { id: legendButton; required property int index; readonly property var channelInfo: root.channelStore.channel(index); text: channelInfo.name + "  " + root.formatNumber(channelInfo.voltsPerDiv) + " V/div" + (channelInfo.enabled ? "" : " · 已停用"); visible: channelInfo.visible; implicitHeight: 26; opacity: channelInfo.enabled ? 1 : .55; contentItem: Text { text: legendButton.text; color: legendButton.channelInfo.color; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } background: Rectangle { radius: 3; color: "#162630"; border.color: root.selectedChannelIndex === index ? channelInfo.color : "#365467" } onClicked: root.selectedChannelRequested(index) } }
            }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; color: "#10242f"; border.color: "#365467"; clip: true
            Canvas {
                id: waveformCanvas; anchors.fill: parent; anchors.margins: 1
                onWidthChanged: { root.rebuildFrame(); root.schedulePaint() }
                onPaint: {
                    const c = getContext("2d"), w = width, h = height; if (w <= 0 || h <= 0) return
                    c.clearRect(0,0,w,h); c.fillStyle="#10242f"; c.fillRect(0,0,w,h)
                    const divW=w/10, divH=h/8
                    if (root.gridVisible) { c.strokeStyle="#173440"; c.lineWidth=1; for(let i=0;i<=50;++i){c.beginPath();c.moveTo(i*divW/5,0);c.lineTo(i*divW/5,h);c.stroke()} for(let i=0;i<=40;++i){c.beginPath();c.moveTo(0,i*divH/5);c.lineTo(w,i*divH/5);c.stroke()} c.strokeStyle="#295363"; for(let i=0;i<=10;++i){c.beginPath();c.moveTo(i*divW,0);c.lineTo(i*divW,h);c.stroke()} for(let i=0;i<=8;++i){c.beginPath();c.moveTo(0,i*divH);c.lineTo(w,i*divH);c.stroke()} }
                    c.strokeStyle="#3b7180"; c.setLineDash([3,4]); c.beginPath(); c.moveTo(0,h/2); c.lineTo(w,h/2); c.stroke(); c.setLineDash([])
                    if (!root.channelStore.hasData) return
                    const end=root.latestSampleTime-root.historyOffsetSeconds, start=end-root.visibleTimeSeconds, first=Math.max(0,Math.ceil((start-root.channelStore.historyStartTime)/root.samplePeriodSeconds)), last=Math.min(root.channelStore.historyCount-1,Math.floor((end-root.channelStore.historyStartTime)/root.samplePeriodSeconds)), budget=Math.max(1024,Math.min(4096,Math.round(w*2)))
                    for(let ch=0; ch<root.channelStore.channelModel.count; ++ch) {
                        const data=root.channelStore.channel(ch); if(!data.visible) continue
                        c.strokeStyle=data.color; c.lineWidth=2; c.beginPath(); let drew=false
                        function point(value,x) { const y=h/2-(value+data.verticalOffsetV)*(divH/data.voltsPerDiv); if(!drew){c.moveTo(x,y);drew=true}else c.lineTo(x,y) }
                        if(!root.usesHistory) { const frame=root.channelStore.updateFrame(ch); for(let i=0;i<frame.length;++i) point(frame[i], frame.length>1?i/(frame.length-1)*w:0) }
                        else { const count=Math.max(0,last-first+1), step=Math.max(1,Math.ceil(count/budget)); for(let l=first;l<=last;l+=step) { const bufferIndex=(root.channelStore.historyStartIndex+l)%root.channelStore.historyCapacity, value=root.channelStore.historyValue(ch, bufferIndex); if(value!==undefined) point(value,(root.channelStore.historyTimes[bufferIndex]-start)/root.visibleTimeSeconds*w) } }
                        if(drew) c.stroke()
                    }
                }
            }
            Label { anchors.centerIn: parent; visible: root.channelStore.visibleChannelCount === 0; text: qsTr("请选择要显示的通道"); color: "#7790a0"; font.pixelSize: 18 }
            Label { anchors.centerIn: parent; visible: root.channelStore.visibleChannelCount > 0 && !root.channelStore.hasData; text: qsTr("等待模拟采集数据"); color: "#7790a0"; font.pixelSize: 18 }
            Label { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12; text: root.formatNumber(root.timePerDivMs)+" ms/div"; color: "#8fa3b4"; font.pixelSize: 12 }
            Label { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 12; text: root.formatTime(-root.historyOffsetSeconds-root.visibleTimeSeconds); color: "#8fa3b4"; font.pixelSize: 12 }
            Label { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12; text: root.formatTime(-root.historyOffsetSeconds); color: "#8fa3b4"; font.pixelSize: 12 }
        }
        RowLayout { Layout.fillWidth: true; spacing: 8; ActionButton { text: qsTr("开始模拟"); enabled: !root.simulationRunning; fillColor: "#168b7c"; onClicked: root.startRequested() } ActionButton { text: qsTr("停止模拟"); enabled: root.simulationRunning; fillColor: "#a1514d"; onClicked: root.stopRequested() } ActionButton { text: qsTr("垂直适配"); fillColor: "#285b73"; onClicked: root.verticalFitRequested() } ActionButton { text: qsTr("位置复位"); fillColor: "#354452"; onClicked: root.resetPositionsRequested() } Item { Layout.fillWidth:true } ActionButton { text: qsTr("清除历史"); fillColor: "#493b3a"; onClicked: root.clearHistoryRequested() } }
    }
}
