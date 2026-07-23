#include "RecorderBackend.h"
#include "AsyncLogWriter.h"

#include <QDataStream>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QStringList>
#include <QtMath>
#include <algorithm>
#include <cmath>

namespace {
constexpr qint64 SafetyMargin = 10LL * 1024 * 1024;
constexpr quint32 FileMagic = 0x4f534352;       // OSCR
constexpr quint32 BlockMagic = 0x424c4b31;      // BLK1
constexpr quint32 BlockCommitted = 0x434d5431;  // CMT1
constexpr int BlockHeaderBytes = 36;
constexpr double Tau = 6.28318530717958647692;
}

RecorderBackend::RecorderBackend(QObject *parent) : QObject(parent)
{
    m_saveDirectory = QDir(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)).filePath("OscRecorder");
    QDir().mkpath(m_saveDirectory);
    m_writeTimer.setInterval(200);
    connect(&m_writeTimer, &QTimer::timeout, this, &RecorderBackend::flushPendingBlocks);
    refreshStorage();
}

QString RecorderBackend::saveDirectory() const { return m_saveDirectory; }
QUrl RecorderBackend::saveDirectoryUrl() const { return QUrl::fromLocalFile(m_saveDirectory); }
QString RecorderBackend::sessionDirectory() const { return m_sessionDirectory; }
QString RecorderBackend::currentFileName() const { return m_currentFileName; }
QString RecorderBackend::status() const { return m_status; }
QString RecorderBackend::statusDetail() const { return m_statusDetail; }
QString RecorderBackend::createdAt() const { return m_createdAt; }
QString RecorderBackend::finishedAt() const { return m_finishedAt; }
bool RecorderBackend::recording() const { return m_status == "recording"; }
qint64 RecorderBackend::totalBytes() const { return m_totalBytes; }
qint64 RecorderBackend::availableBytes() const { return m_availableBytes; }
qint64 RecorderBackend::theoreticalBytesPerSecond() const { return m_theoreticalBytesPerSecond; }
qint64 RecorderBackend::simulatedFileBytes() const { return m_simulatedFileBytes; }
qint64 RecorderBackend::recordedMilliseconds() const { return m_recordedMilliseconds; }

void RecorderBackend::setStatus(const QString &value, const QString &detail) { m_status = value; m_statusDetail = detail; emit recordingStateChanged(); }
void RecorderBackend::setSaveDirectory(const QString &path) { if (recording()) { emit eventLogged(tr("录制中不能修改保存路径。"), "NOTICE"); return; } if (path.isEmpty()) return; m_saveDirectory = QDir::cleanPath(path); emit saveDirectoryChanged(); refreshStorage(); }
void RecorderBackend::setSaveDirectoryUrl(const QUrl &url) { if (!url.isLocalFile()) { setStatus("not_ready", tr("请选择本地文件系统目录。")); return; } setSaveDirectory(url.toLocalFile()); }
void RecorderBackend::setRecordingParameters(int sampleRate, int enabledChannels) { if (recording()) return; m_sampleRate = sampleRate; m_theoreticalBytesPerSecond = qint64(sampleRate) * enabledChannels * 4; emit recordingStateChanged(); }

void RecorderBackend::refreshStorage()
{
    QStorageInfo storage(m_saveDirectory);
    m_totalBytes = storage.isValid() && storage.isReady() ? storage.bytesTotal() : 0;
    m_availableBytes = storage.isValid() && storage.isReady() ? storage.bytesAvailable() : 0;
    if (!recording() && m_status != "completed") setStatus(m_totalBytes ? "ready" : "not_ready", m_totalBytes ? QString() : tr("保存目录不存在或文件系统未就绪。"));
    emit storageChanged();
}

bool RecorderBackend::prepareDirectory(QString *reason)
{
    QFileInfo info(m_saveDirectory); QStorageInfo storage(m_saveDirectory);
    if (!info.exists() || !info.isDir()) { *reason = tr("保存目录不存在：%1").arg(m_saveDirectory); return false; }
    if (!info.isWritable()) { *reason = tr("保存目录不可写：%1").arg(m_saveDirectory); return false; }
    if (!storage.isValid() || !storage.isReady()) { *reason = tr("目标文件系统未就绪。"); return false; }
    m_totalBytes = storage.bytesTotal(); m_availableBytes = storage.bytesAvailable();
    if (m_availableBytes < qMax(SafetyMargin, m_theoreticalBytesPerSecond * 5)) { *reason = tr("可用空间不足。"); return false; }
    return true;
}

bool RecorderBackend::startRecording(int sampleRate, const QVariantList &channelIds, const QString &mode, bool acquisitionRunning)
{
    if (!acquisitionRunning) { setStatus("not_ready", tr("请先开始采集，再开始录制。")); return false; }
    if (recording()) return false;
    m_channelIds.clear(); for (const QVariant &id : channelIds) m_channelIds.append(id.toInt());
    setRecordingParameters(sampleRate, m_channelIds.size()); m_acquisitionMode = mode;
    QString reason;
    if (m_channelIds.isEmpty() || !prepareDirectory(&reason)) { setStatus(reason.contains(tr("空间")) ? "insufficient_space" : "path_not_writable", reason.isEmpty() ? tr("没有已启用采集通道。") : reason); return false; }
    const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss_zzz");
    m_temporarySessionDirectory = QDir(m_saveDirectory).filePath("recording_in_progress_" + stamp);
    m_sessionDirectory = m_temporarySessionDirectory;
    if (!QDir().mkpath(m_sessionDirectory)) { setStatus("write_error", tr("无法创建会话目录。")); return false; }
    m_currentFileName = "waveform.part";
    m_dataFile.setFileName(QDir(m_sessionDirectory).filePath(m_currentFileName));
    m_indexFile.setFileName(QDir(m_sessionDirectory).filePath("index.csv"));
    m_logFile.setFileName(QDir(m_sessionDirectory).filePath("recording.log"));
    if (!m_dataFile.open(QIODevice::WriteOnly) || !m_indexFile.open(QIODevice::WriteOnly | QIODevice::Text)) { writeLog("ERROR recording file creation failed"); setStatus("write_error", tr("无法创建录制文件。")); return false; }
    QDataStream header(&m_dataFile); header.setByteOrder(QDataStream::LittleEndian);
    header << FileMagic << quint32(2) << qint64(QDateTime::currentMSecsSinceEpoch()) << qint32(m_sampleRate) << qint32(m_channelIds.size());
    for (int id : m_channelIds) header << qint32(id);
    m_indexFile.write("relative_start_seconds,first_sample,count,file_offset,payload_bytes,crc32,committed\n");
    m_createdAt = QDateTime::currentDateTime().toString(Qt::ISODateWithMs); m_finishedAt.clear(); m_simulatedFileBytes = m_dataFile.size(); m_recordedMilliseconds = 0;
    m_nextSample = 0; m_gapCount = 0; m_hasFirstBlockTime = false; m_pendingBlocks.clear(); m_recordingClock.start();
    setStatus("recording"); writeLog("created waveform.part, index.csv and recording.log"); writeSessionMetadata(); m_writeTimer.start();
    emit eventLogged(tr("模拟录制已开始。"), "INFO"); return true;
}

void RecorderBackend::enqueueRawSampleBlock(double startTimeSeconds, const QByteArray &payload, bool hasGap)
{
    if (!recording() || m_channelIds.isEmpty() || payload.isEmpty()) return;
    const int bytesPerSample = m_channelIds.size() * int(sizeof(float));
    if (bytesPerSample <= 0 || payload.size() % bytesPerSample != 0) {
        writeLog("ERROR raw block layout is not float32 sample-major interleaved");
        setStatus("write_error", tr("原始采样块格式无效。"));
        return;
    }
    const quint32 count = quint32(payload.size() / bytesPerSample);
    if (!m_hasFirstBlockTime) { m_firstBlockTime = startTimeSeconds; m_hasFirstBlockTime = true; }
    m_pendingBlocks.append({startTimeSeconds, m_nextSample, count, payload, hasGap});
    m_nextSample += quint64(count);
    if (hasGap) ++m_gapCount;
}

quint32 RecorderBackend::crc32(const QByteArray &data) const
{
    quint32 crc = 0xffffffffU;
    for (const auto byte : data) { crc ^= quint8(byte); for (int bit = 0; bit < 8; ++bit) crc = (crc >> 1) ^ (0xedb88320U & -(crc & 1U)); }
    return ~crc;
}

bool RecorderBackend::writeBlock(const Block &block)
{
    // The recorder receives the exact post-event float32 bytes generated by
    // RealtimeDataBackend.  It must never synthesize a second waveform.
    const QByteArray &payload = block.payload;
    if (payload.size() != int(block.count) * m_channelIds.size() * int(sizeof(float))) return false;
    /* Previous independent waveform generator intentionally removed from the
       data path.  It is retained below as disabled source context only.
    QByteArray payload;
    QDataStream samples(&payload, QIODevice::WriteOnly);
    samples.setByteOrder(QDataStream::LittleEndian);
    samples.setFloatingPointPrecision(QDataStream::SinglePrecision);
    for (quint32 sample = 0; sample < block.count; ++sample) {
        const double time = block.startTime + double(sample) / m_sampleRate;
        for (int channel : m_channelIds) {
            // Mirror RealtimeDataBackend::valueFor(): the recorder follows the
            // same shared sample clock and per-channel base-waveform family.
            const int channelId = channel + 1;
            const int type = channel % 8;
            const double nyquist = m_sampleRate * .5;
            const double requestedFrequency = 70.0 + (channelId % 11) * 43.0 + (channelId / 8) * 17.0;
            const double frequency = std::min(requestedFrequency, std::max(1.0, nyquist * (type == 3 ? .18 : .35)));
            const double amplitude = .35 + ((channelId * 3) % 7) * .09;
            const double phase = channelId * .413;
            const double offset = ((channelId * 5) % 7 - 3) * .08;
            const double angle = Tau * frequency * time + phase;
            const double cycle = frequency * time + phase / Tau;
            const double unitCycle = cycle - std::floor(cycle);
            double waveform = 0.0;
            switch (type) {
            case 0: waveform = qSin(angle) >= 0.0 ? 1.0 : -1.0; break;
            case 1: waveform = 4.0 / Tau * qAsin(qSin(angle)); break;
            case 2: waveform = 2.0 * unitCycle - 1.0; break;
            case 3: waveform = .68 * qSin(angle) + .32 * qSin(Tau * std::min(frequency * 1.73, nyquist * .42) * time + phase * 1.7); break;
            case 4: waveform = qSin(angle); break;
            case 5: {
                quint32 hash = quint32(block.firstSample + sample) ^ (quint32(channelId) * 0x9e3779b9U);
                hash ^= hash << 13; hash ^= hash >> 17; hash ^= hash << 5;
                waveform = qSin(angle) + .055 * (double(hash & 0xffffU) / 32767.5 - 1.0);
                break;
            }
            case 6: waveform = unitCycle < (.12 + (channelId % 4) * .04) ? 1.0 : -.32; break;
            case 7: waveform = (.42 + .58 * qSin(Tau * frequency * .11 * time + phase * .6)) * qSin(angle); break;
            }
            samples << float((type == 4 ? offset * 1.8 : offset) + amplitude * waveform);
        }
    }
    if (samples.status() != QDataStream::Ok) return false;
    */
    const qint64 offset = m_dataFile.pos();
    const double relativeStart = block.startTime - m_firstBlockTime;
    const float storedRelativeStart = float(relativeStart);
    const quint32 checksum = crc32(payload);
    QDataStream header(&m_dataFile); header.setByteOrder(QDataStream::LittleEndian); header.setFloatingPointPrecision(QDataStream::SinglePrecision);
    header << BlockMagic << storedRelativeStart << block.firstSample << block.count << quint32(block.hasGap ? 1 : 0) << quint32(payload.size()) << checksum << quint32(0);
    if (header.status() != QDataStream::Ok || m_dataFile.write(payload) != payload.size() || !m_dataFile.flush()) return false;
    if (!m_dataFile.seek(offset + BlockHeaderBytes - 4)) return false;
    QDataStream commit(&m_dataFile); commit.setByteOrder(QDataStream::LittleEndian); commit << BlockCommitted;
    if (commit.status() != QDataStream::Ok || !m_dataFile.flush()) return false;
    m_dataFile.seek(offset + BlockHeaderBytes + payload.size());
    m_indexFile.write(QByteArray::number(relativeStart, 'f', 9) + ',' + QByteArray::number(block.firstSample) + ',' + QByteArray::number(block.count) + ',' + QByteArray::number(offset) + ',' + QByteArray::number(payload.size()) + ',' + QByteArray::number(checksum) + ",1\n");
    return true;
}

void RecorderBackend::flushPendingBlocks()
{
    if (!recording()) return;
    while (!m_pendingBlocks.isEmpty()) { const Block block = m_pendingBlocks.takeFirst(); if (!writeBlock(block)) { writeLog("ERROR block write failed"); setStatus("write_error", tr("原始波形文件写入失败。")); m_writeTimer.stop(); m_dataFile.close(); m_indexFile.close(); m_logFile.close(); return; } }
    m_dataFile.flush(); m_indexFile.flush(); m_recordedMilliseconds = m_recordingClock.elapsed(); m_simulatedFileBytes = m_dataFile.size(); refreshStorage(); emit recordingStateChanged();
}

bool RecorderBackend::validateIndex(QString *reason)
{
    QFile raw(m_dataFile.fileName()), index(m_indexFile.fileName());
    if (!raw.open(QIODevice::ReadOnly) || !index.open(QIODevice::ReadOnly | QIODevice::Text)) { *reason = tr("无法重新打开数据或索引文件进行校验。"); return false; }
    index.readLine(); quint64 expectedFirst = 0; qint64 expectedEnd = 0; bool any = false;
    while (!index.atEnd()) {
        const QStringList fields = QString::fromUtf8(index.readLine()).trimmed().split(','); if (fields.size() != 7) { *reason = tr("索引字段数量错误。"); return false; }
        const quint64 first = fields[1].toULongLong(); const quint32 count = fields[2].toUInt(); const qint64 offset = fields[3].toLongLong(); const quint32 bytes = fields[4].toUInt(); const quint32 checksum = fields[5].toUInt();
        if (first != expectedFirst || !raw.seek(offset)) { *reason = tr("索引样本序号或偏移不连续。"); return false; }
        QDataStream header(&raw); header.setByteOrder(QDataStream::LittleEndian); header.setFloatingPointPrecision(QDataStream::SinglePrecision);
        quint32 magic = 0, actualCount = 0, flags = 0, actualBytes = 0, actualCrc = 0, committed = 0; float relative = 0; quint64 actualFirst = 0;
        header >> magic >> relative >> actualFirst >> actualCount >> flags >> actualBytes >> actualCrc >> committed;
        const QByteArray payload = raw.read(actualBytes);
        if (magic != BlockMagic || actualFirst != first || actualCount != count || actualBytes != bytes || actualCrc != checksum || committed != BlockCommitted || payload.size() != int(actualBytes) || crc32(payload) != actualCrc) { *reason = tr("索引与块头、CRC或提交标记不一致。"); return false; }
        expectedFirst += count; expectedEnd = offset + BlockHeaderBytes + actualBytes; any = true;
    }
    if (any && raw.size() != expectedEnd) { *reason = tr("索引记录的末尾偏移与数据文件大小不一致。"); return false; }
    return true;
}

void RecorderBackend::writeLog(const QString &line)
{
    if (m_logFile.fileName().isEmpty()) return;
    AsyncLogWriter::appendRecording(m_logFile.fileName(), QDateTime::currentDateTime().toString(Qt::ISODateWithMs) + " " + line);
}

void RecorderBackend::writeSessionMetadata()
{
    QJsonArray ids; for (int id : m_channelIds) { QJsonObject channel; channel["zeroBasedIndex"] = id; channel["displayName"] = QStringLiteral("CH%1").arg(id + 1); ids.append(channel); }
    const QDateTime started = QDateTime::fromString(m_createdAt, Qt::ISODateWithMs);
    const QDateTime finished = QDateTime::fromString(m_finishedAt, Qt::ISODateWithMs);
    const double wallDurationSeconds = started.isValid() && finished.isValid() ? double(started.msecsTo(finished)) / 1000.0 : 0.0;
    const double activeRecordingSeconds = double(m_recordedMilliseconds) / 1000.0;
    const double dataDurationSeconds = m_sampleRate > 0 ? double(m_nextSample) / double(m_sampleRate) : 0.0;
    QJsonObject object; object["formatVersion"] = 2; object["sampleType"] = "float32"; object["byteOrder"] = "little-endian"; object["channelIds"] = ids; object["sampleRate"] = m_sampleRate; object["sampleCount"] = double(m_nextSample); object["dataDurationSeconds"] = dataDurationSeconds; object["wallDurationSeconds"] = wallDurationSeconds; object["activeRecordingSeconds"] = activeRecordingSeconds; object["acquisitionMode"] = m_acquisitionMode; object["startedAt"] = m_createdAt; object["finishedAt"] = m_finishedAt; object["dataFile"] = m_currentFileName; object["dataBytes"] = double(m_simulatedFileBytes); object["gapCount"] = double(m_gapCount); object["finalStatus"] = m_status;
    QFile file(QDir(m_sessionDirectory).filePath("session.json")); if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
}

void RecorderBackend::stopRecording()
{
    if (!recording()) return;
    setStatus("stopping", tr("正在完成当前写入并封存文件。")); writeLog("stop requested: safe flush started"); m_writeTimer.stop();
    while (!m_pendingBlocks.isEmpty()) { const Block block = m_pendingBlocks.takeFirst(); if (!writeBlock(block)) { writeLog("ERROR stop flush failed"); setStatus("write_error", tr("停止时写入失败。")); return; } }
    m_recordedMilliseconds = m_recordingClock.elapsed(); m_simulatedFileBytes = m_dataFile.size(); m_dataFile.flush(); m_indexFile.flush(); m_dataFile.close(); m_indexFile.close(); QString reason;
    if (!validateIndex(&reason)) { writeLog("ERROR index validation failed: " + reason); setStatus("write_error", reason); return; }
    writeLog("sealed waveform.part after index validation");
    // The session directory is renamed below; drain its short, state-only log
    // before changing the path so no queued entries are stranded.
    AsyncLogWriter::flushRecording(m_logFile.fileName());
    const QString partPath = QDir(m_sessionDirectory).filePath("waveform.part"), dataPath = QDir(m_sessionDirectory).filePath("waveform.bin");
    if (!QFile::rename(partPath, dataPath)) { setStatus("write_error", tr("无法封存 .part 数据文件。")); return; }
    m_currentFileName = "waveform.bin"; m_finishedAt = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
    const QString finalDirectory = QDir(m_saveDirectory).filePath("recording_" + QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss_zzz"));
    if (QDir(m_saveDirectory).rename(QFileInfo(m_temporarySessionDirectory).fileName(), QFileInfo(finalDirectory).fileName())) m_sessionDirectory = finalDirectory;
    m_logFile.setFileName(QDir(m_sessionDirectory).filePath("recording.log"));
    writeLog("waveform.part validation completed; renamed waveform.part to waveform.bin");
    AsyncLogWriter::flushRecording(m_logFile.fileName());
    setStatus("completed"); writeSessionMetadata(); refreshStorage(); emit eventLogged(tr("模拟录制已完成。"), "INFO");
}
