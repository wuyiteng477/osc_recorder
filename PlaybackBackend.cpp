#include "PlaybackBackend.h"

#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QStringList>

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>
#include <vector>

namespace {
constexpr quint32 FileMagic = 0x4f534352;
constexpr quint32 BlockMagic = 0x424c4b31;
constexpr quint32 BlockCommitted = 0x434d5431;
constexpr int BlockHeaderBytes = 36;
constexpr quint32 MatMiInt8 = 1;
constexpr quint32 MatMiInt32 = 5;
constexpr quint32 MatMiUInt16 = 4;
constexpr quint32 MatMiUInt32 = 6;
constexpr quint32 MatMiSingle = 7;
constexpr quint32 MatMiDouble = 9;
constexpr quint32 MatMiMatrix = 14;
constexpr quint32 MatMxCharClass = 4;
constexpr quint32 MatMxSingleClass = 7;
constexpr quint32 MatMxDoubleClass = 6;
constexpr quint64 MatMaxElementBytes = 0xffffffffULL;

quint64 matPaddedBytes(quint64 bytes)
{
    return (bytes + 7ULL) & ~7ULL;
}

QByteArray matTag(quint32 type, quint32 bytes)
{
    QByteArray tag;
    QDataStream stream(&tag, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::LittleEndian);
    stream << type << bytes;
    return tag;
}
}

PlaybackBackend::PlaybackBackend(QObject *parent) : QObject(parent)
{
    m_exportTimer.setInterval(0);
    connect(&m_exportTimer, &QTimer::timeout, this, &PlaybackBackend::writeNextDataExportBlock);
}
QString PlaybackBackend::status() const { return m_status; }
QString PlaybackBackend::detail() const { return m_detail; }
QString PlaybackBackend::sessionDirectory() const { return m_sessionDirectory; }
QString PlaybackBackend::startedAt() const { return m_startedAt; }
QString PlaybackBackend::finishedAt() const { return m_finishedAt; }
int PlaybackBackend::sampleRate() const { return m_sampleRate; }
double PlaybackBackend::durationSeconds() const { return m_durationSeconds; }
qint64 PlaybackBackend::dataBytes() const { return m_dataBytes; }
quint64 PlaybackBackend::gapCount() const { return m_gapCount; }
QVariantList PlaybackBackend::channels() const { return m_channels; }
QVariantList PlaybackBackend::frames() const { return m_frames; }
int PlaybackBackend::displayedChannelCount() const { return m_displayIds.size(); }
double PlaybackBackend::viewStartSeconds() const { return m_viewStart; }
double PlaybackBackend::viewDurationSeconds() const { return m_viewDuration; }
bool PlaybackBackend::exportingData() const { return m_exportingCsv; }
QString PlaybackBackend::exportDetail() const { return m_exportDetail; }

bool PlaybackBackend::fail(const QString &message)
{
    m_status = QStringLiteral("error"); m_detail = message; m_frames.clear(); emit changed(); emit eventLogged(message, "ERROR"); return false;
}

quint32 PlaybackBackend::crc32(const QByteArray &data) const
{
    quint32 crc = 0xffffffffU;
    for (const auto byte : data) { crc ^= quint8(byte); for (int bit = 0; bit < 8; ++bit) crc = (crc >> 1) ^ (0xedb88320U & -(crc & 1U)); }
    return ~crc;
}

bool PlaybackBackend::loadSessionUrl(const QUrl &url)
{
    if (!url.isLocalFile()) return fail(tr("请选择本地录制会话目录或 session.json。"));
    return loadSessionPath(url.toLocalFile());
}

bool PlaybackBackend::loadSessionPath(const QString &path)
{
    const QFileInfo info(path);
    const QString directory = info.isDir() ? info.absoluteFilePath() : info.absolutePath();
    const QString sessionPath = info.isDir() ? QDir(directory).filePath("session.json") : info.absoluteFilePath();
    return parseAndValidate(directory, sessionPath);
}

bool PlaybackBackend::parseAndValidate(const QString &directory, const QString &sessionPath)
{
    QFile session(sessionPath);
    if (!session.open(QIODevice::ReadOnly)) return fail(tr("无法打开 session.json。"));
    QJsonParseError error; const QJsonDocument document = QJsonDocument::fromJson(session.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) return fail(tr("session.json 格式无效。"));
    const QJsonObject object = document.object();
    if (object.value("formatVersion").toInt() != 2) return fail(tr("不支持的录制格式版本。"));
    if (object.value("finalStatus").toString() != "completed") return fail(tr("录制未完成，不能回放。"));
    if (object.value("sampleType").toString() != "float32" || object.value("byteOrder").toString() != "little-endian") return fail(tr("不支持的数据类型或字节序。"));
    const QString dataName = object.value("dataFile").toString();
    if (dataName != "waveform.bin") return fail(tr("会话未封存 waveform.bin。"));
    const QJsonArray ids = object.value("channelIds").toArray();
    if (ids.isEmpty()) return fail(tr("会话未记录采集通道。"));

    m_channelIds.clear(); m_channels.clear();
    for (const QJsonValue &value : ids) {
        const QJsonObject item = value.toObject(); const int id = item.value("zeroBasedIndex").toInt(-1);
        if (id < 0) return fail(tr("通道编号无效。"));
        m_channelIds.append(id);
        QVariantMap map; map["id"] = id; map["name"] = item.value("displayName").toString(QStringLiteral("CH%1").arg(id + 1)); map["enabled"] = m_channelIds.size() <= 8;
        m_channels.append(map);
    }
    m_channelCount = m_channelIds.size(); m_sampleRate = object.value("sampleRate").toInt(); m_sampleCount = quint64(object.value("sampleCount").toDouble());
    m_durationSeconds = object.value("dataDurationSeconds").toDouble(); m_dataBytes = qint64(object.value("dataBytes").toDouble()); m_gapCount = quint64(object.value("gapCount").toDouble());
    m_startedAt = object.value("startedAt").toString(); m_finishedAt = object.value("finishedAt").toString(); m_sessionDirectory = directory; m_dataPath = QDir(directory).filePath(dataName);
    if (m_sampleRate <= 0 || m_durationSeconds < 0 || !QFileInfo::exists(m_dataPath)) return fail(tr("采样率、时长或 waveform.bin 无效。"));
    const double samplePeriod = 1.0 / double(m_sampleRate);
    const double expectedDuration = double(m_sampleCount) * samplePeriod;
    if (std::abs(m_durationSeconds - expectedDuration) > samplePeriod * .5)
        return fail(tr("session.json 的数据时长与采样率、样本数不一致。"));
    if (QFileInfo(m_dataPath).size() != m_dataBytes) return fail(tr("waveform.bin 文件大小与 session.json 不一致。"));

    QFile index(QDir(directory).filePath("index.csv"));
    if (!index.open(QIODevice::ReadOnly | QIODevice::Text)) return fail(tr("缺少或无法读取 index.csv。"));
    if (!index.readLine().startsWith("relative_start_seconds")) return fail(tr("index.csv 表头不受支持。"));
    m_blocks.clear(); quint64 expectedFirst = 0; qint64 expectedEnd = 0;
    while (!index.atEnd()) {
        const QStringList fields = QString::fromUtf8(index.readLine()).trimmed().split(',');
        if (fields.size() != 7) return fail(tr("index.csv 字段数量错误。"));
        Block block; block.start = fields[0].toDouble(); block.first = fields[1].toULongLong(); block.count = fields[2].toUInt(); block.offset = fields[3].toLongLong(); block.bytes = fields[4].toUInt(); block.crc = fields[5].toUInt();
        if (fields[6] != "1" || block.first != expectedFirst || block.count == 0 || block.bytes != block.count * quint32(m_channelCount) * 4) return fail(tr("index.csv 样本序号、提交标记或数据长度无效。"));
        const double expectedStart = double(block.first) / double(m_sampleRate);
        if (std::abs(block.start - expectedStart) > qMax(1e-6, 1.0 / double(m_sampleRate)))
            return fail(tr("index.csv 的块开始时间与样本序号、采样率不一致。"));
        if (!validateBlock(block)) return false;
        expectedFirst += block.count; expectedEnd = block.offset + BlockHeaderBytes + block.bytes; m_blocks.append(block);
    }
    if (m_blocks.isEmpty() || expectedFirst != m_sampleCount || QFileInfo(m_dataPath).size() != expectedEnd) return fail(tr("索引记录与数据文件大小或样本数不一致。"));
    m_displayIds = m_channelIds.mid(0, 8); m_viewDuration = qMin(qMax(samplePeriod, m_durationSeconds), .1); m_viewStart = qMax(0.0, m_durationSeconds - m_viewDuration);
    m_status = QStringLiteral("ready"); m_detail = tr("会话校验完成。"); loadWindow(); emit eventLogged(tr("历史录制会话已加载。"), "INFO"); return true;
}

bool PlaybackBackend::validateBlock(const Block &block, QByteArray *payload)
{
    QFile raw(m_dataPath); if (!raw.open(QIODevice::ReadOnly) || !raw.seek(block.offset)) return fail(tr("无法定位数据块。"));
    QDataStream stream(&raw); stream.setByteOrder(QDataStream::LittleEndian); stream.setFloatingPointPrecision(QDataStream::SinglePrecision);
    quint32 magic = 0, count = 0, flags = 0, bytes = 0, crc = 0, committed = 0; quint64 first = 0; float relative = 0;
    stream >> magic >> relative >> first >> count >> flags >> bytes >> crc >> committed;
    const QByteArray data = raw.read(bytes);
    if (stream.status() != QDataStream::Ok || magic != BlockMagic || first != block.first || count != block.count || bytes != block.bytes || crc != block.crc || committed != BlockCommitted || data.size() != int(bytes) || crc32(data) != crc) return fail(tr("数据块 CRC、提交标记或索引不一致。"));
    if (payload) *payload = data;
    return true;
}

void PlaybackBackend::setDisplayChannels(const QVariantList &ids)
{
    QList<int> next; for (const QVariant &value : ids) { const int id = value.toInt(); if (m_channelIds.contains(id) && !next.contains(id) && next.size() < 8) next.append(id); }
    m_displayIds = next;
    for (int index = 0; index < m_channels.size(); ++index) {
        QVariantMap channel = m_channels[index].toMap();
        channel["enabled"] = m_displayIds.contains(channel.value("id").toInt());
        m_channels[index] = channel;
    }
    loadWindow();
}

bool PlaybackBackend::toggleDisplayChannel(int zeroBasedId, bool selected)
{
    if (!m_channelIds.contains(zeroBasedId)) return false;
    QList<int> next = m_displayIds;
    if (selected) {
        if (next.contains(zeroBasedId)) return true;
        if (next.size() >= 8) { m_detail = tr("最多同时显示8个通道。"); emit changed(); return false; }
        next.append(zeroBasedId);
    } else {
        next.removeAll(zeroBasedId);
    }
    QVariantList values; for (int id : next) values.append(id);
    setDisplayChannels(values);
    m_detail = next.isEmpty() ? tr("请选择至少一个回放通道。") : tr("当前时间窗口已更新。");
    emit changed();
    return true;
}

void PlaybackBackend::setView(double start, double duration)
{
    if (m_status != "ready" || m_sampleRate <= 0)
        return;

    // Playback positions are always snapped to the file's real sample grid.
    // This prevents sub-sample UI values from selecting different visual frames
    // without advancing an actual recorded sample.
    const double samplePeriod = 1.0 / double(m_sampleRate);
    const double maximumDuration = qMax(samplePeriod, m_durationSeconds);
    const double boundedDuration = qBound(samplePeriod, duration, maximumDuration);
    const auto durationSamples = qMax<qint64>(1, qRound64(boundedDuration / samplePeriod));
    m_viewDuration = qMin(maximumDuration, double(durationSamples) * samplePeriod);

    const double maximumStart = qMax(0.0, m_durationSeconds - m_viewDuration);
    const auto startSample = qMax<qint64>(0, qRound64(qBound(0.0, start, maximumStart) / samplePeriod));
    m_viewStart = qMin(maximumStart, double(startSample) * samplePeriod);
    loadWindow();
}
void PlaybackBackend::moveView(double seconds) { setView(m_viewStart + seconds, m_viewDuration); }

QVariantMap PlaybackBackend::measureWindow(int zeroBasedChannelId, double startSeconds, double endSeconds)
{
    QVariantMap result{{"valid", false}, {"periodValid", false}};
    if (m_status != QStringLiteral("ready") || m_sampleRate <= 0 || endSeconds <= startSeconds)
        return result;
    const int sourceIndex = m_channelIds.indexOf(zeroBasedChannelId);
    if (sourceIndex < 0)
        return result;

    const double samplePeriod = 1.0 / double(m_sampleRate);
    const quint64 firstSample = quint64(std::max<qint64>(0, qint64(std::ceil((startSeconds - 1e-12) / samplePeriod))));
    const qint64 lastSampleSigned = qint64(std::floor((endSeconds + 1e-12) / samplePeriod));
    if (lastSampleSigned < 0)
        return result;
    const quint64 lastSample = quint64(lastSampleSigned);
    if (lastSample < firstSample || lastSample - firstSample + 1 < 8)
        return result;

    double sum = 0.0, sumSquares = 0.0;
    float minimum = std::numeric_limits<float>::infinity(), maximum = -std::numeric_limits<float>::infinity();
    quint64 count = 0;
    std::vector<std::pair<quint64, float>> samples;
    samples.reserve(size_t(std::min<quint64>(lastSample - firstSample + 1, 262144)));
    for (const Block &block : m_blocks) {
        if (block.first + block.count <= firstSample || block.first > lastSample)
            continue;
        QByteArray payload;
        if (!validateBlock(block, &payload))
            return result;
        QDataStream stream(payload);
        stream.setByteOrder(QDataStream::LittleEndian);
        stream.setFloatingPointPrecision(QDataStream::SinglePrecision);
        for (quint32 sample = 0; sample < block.count; ++sample) {
            float selected = 0.0F;
            for (int source = 0; source < m_channelCount; ++source) {
                float value = 0.0F;
                stream >> value;
                if (source == sourceIndex)
                    selected = value;
            }
            const quint64 sampleIndex = block.first + sample;
            if (sampleIndex < firstSample || sampleIndex > lastSample)
                continue;
            if (!std::isfinite(selected))
                return result;
            samples.emplace_back(sampleIndex, selected);
            minimum = std::min(minimum, selected);
            maximum = std::max(maximum, selected);
            sum += selected;
            sumSquares += double(selected) * selected;
            ++count;
        }
    }
    if (count < 8 || samples.size() != count)
        return result;
    const double mean = sum / double(count);
    result.insert("valid", true);
    result.insert("maximum", maximum);
    result.insert("minimum", minimum);
    result.insert("peakToPeak", double(maximum) - minimum);
    result.insert("mean", mean);
    result.insert("rms", std::sqrt(sumSquares / double(count)));

    std::vector<double> crossings;
    for (size_t index = 1; index < samples.size(); ++index) {
        const float previous = samples[index - 1].second, current = samples[index].second;
        if (previous <= mean && current > mean) {
            const double span = double(current) - previous;
            const double fraction = std::abs(span) > 1e-12 ? (mean - previous) / span : 0.0;
            crossings.push_back((double(samples[index - 1].first) + std::clamp(fraction, 0.0, 1.0)) * samplePeriod);
        }
    }
    if (crossings.size() < 3)
        return result;
    double periodSum = 0.0;
    for (size_t index = 1; index < crossings.size(); ++index) periodSum += crossings[index] - crossings[index - 1];
    const double period = periodSum / double(crossings.size() - 1);
    if (!std::isfinite(period) || period <= 0.0)
        return result;
    double variance = 0.0;
    for (size_t index = 1; index < crossings.size(); ++index) {
        const double delta = crossings[index] - crossings[index - 1] - period;
        variance += delta * delta;
    }
    if (std::sqrt(variance / double(crossings.size() - 1)) / period > 0.12)
        return result;
    result.insert("periodValid", true);
    result.insert("period", period);
    result.insert("frequency", 1.0 / period);
    return result;
}
void PlaybackBackend::resetView() { setView(qMax(0.0, m_durationSeconds - m_viewDuration), m_viewDuration); }

QUrl PlaybackBackend::suggestedExportUrl(const QString &rangeTag, const QString &format) const
{
    if (m_sessionDirectory.isEmpty())
        return {};
    const QString sessionName = QFileInfo(m_sessionDirectory).fileName();
    const QString safeTag = rangeTag.isEmpty() ? QStringLiteral("export") : rangeTag;
    const QString extension = format == QStringLiteral("float32") ? QStringLiteral(".f32")
        : format == QStringLiteral("mat") ? QStringLiteral(".mat") : QStringLiteral(".csv");
    return QUrl::fromLocalFile(QDir(m_sessionDirectory).filePath(sessionName + QStringLiteral("_") + safeTag + extension));
}

bool PlaybackBackend::beginDataExport(const QUrl &outputUrl, bool wholeRecord, bool allRecordedChannels, const QString &format)
{
    if (m_status != "ready" || m_exportingCsv)
        return false;
    if (format != QStringLiteral("csv") && format != QStringLiteral("float32") && format != QStringLiteral("mat")) {
        m_exportDetail = tr("不支持的导出格式。");
        emit changed();
        return false;
    }
    if (!outputUrl.isLocalFile()) {
        m_exportDetail = tr("请选择本地导出保存路径。");
        emit changed();
        return false;
    }

    m_exportChannelIds = allRecordedChannels ? m_channelIds : m_displayIds;
    if (m_exportChannelIds.isEmpty()) {
        m_exportDetail = tr("没有可导出的通道。");
        emit changed();
        return false;
    }

    m_exportSourceIndexes.clear();
    for (int id : m_exportChannelIds) {
        const int sourceIndex = m_channelIds.indexOf(id);
        if (sourceIndex < 0) {
            m_exportDetail = tr("导出通道索引无效。");
            emit changed();
            return false;
        }
        m_exportSourceIndexes.append(sourceIndex);
    }

    const QString outputPath = outputUrl.toLocalFile();
    QFileInfo outputInfo(outputPath);
    if (!QDir(outputInfo.absolutePath()).exists()) {
        m_exportDetail = tr("导出保存目录不存在。");
        emit changed();
        return false;
    }
    if (QFileInfo::exists(outputPath) && !QFileInfo(outputPath).isWritable()) {
        m_exportDetail = tr("导出目标文件不可写。");
        emit changed();
        return false;
    }

    m_exportFile.setFileName(outputPath);
    QIODevice::OpenMode openMode = QIODevice::WriteOnly | QIODevice::Truncate;
    // Float32 is an opaque byte stream.  In particular, do not enable Text:
    // it may translate line endings on Windows and corrupt the byte count.
    if (format == QStringLiteral("csv"))
        openMode |= QIODevice::Text;
    if (!m_exportFile.open(openMode)) {
        m_exportDetail = format == QStringLiteral("csv")
            ? tr("无法创建 CSV 文件。")
            : tr("无法创建二进制导出文件。");
        emit changed();
        return false;
    }

    m_exportStart = wholeRecord ? 0.0 : m_viewStart;
    m_exportEnd = wholeRecord ? m_durationSeconds : qMin(m_durationSeconds, m_viewStart + m_viewDuration);
    m_exportBlockIndex = 0;
    m_exportSampleCount = 0;
    m_exportFormat = format;
    const double samplePeriod = 1.0 / double(m_sampleRate);
    m_exportFirstSample = quint64(qBound(qint64(0), qint64(std::ceil(m_exportStart / samplePeriod - 1e-9)), qint64(m_sampleCount)));
    const qint64 finalSample = qBound(qint64(-1), qint64(std::floor(m_exportEnd / samplePeriod + 1e-9)), qint64(m_sampleCount) - 1);
    m_exportExpectedSampleCount = finalSample >= qint64(m_exportFirstSample)
        ? quint64(finalSample - qint64(m_exportFirstSample) + 1) : 0;
    if (m_exportFormat == QStringLiteral("csv")) {
        QByteArray header("relative_time_s");
        for (int id : m_exportChannelIds)
            header += ",CH" + QByteArray::number(id + 1);
        header += '\n';
        if (m_exportFile.write(header) != header.size()) {
            finishDataExport(tr("CSV 表头写入失败。"), "ERROR");
            return false;
        }
    }

    if (m_exportFormat == QStringLiteral("mat")) {
        QString matError;
        if (!beginMatExport(&matError)) {
            m_exportFile.close();
            m_exportDetail = tr("MAT 文件初始化失败：%1").arg(matError);
            emit changed();
            return false;
        }
    }

    m_exportingCsv = true;
    m_exportDetail = m_exportFormat == QStringLiteral("csv") ? tr("正在导出 CSV…")
        : m_exportFormat == QStringLiteral("float32") ? tr("正在导出 Float32 数据…") : tr("正在导出 MAT 数据…");
    emit changed();
    emit eventLogged(m_exportFormat == QStringLiteral("csv") ? tr("CSV 导出已开始。")
        : m_exportFormat == QStringLiteral("float32") ? tr("Float32+JSON 导出已开始。") : tr("MAT 导出已开始。"), "INFO");
    m_exportTimer.start();
    return true;
}

void PlaybackBackend::finishDataExport(const QString &detail, const QString &level)
{
    m_exportTimer.stop();
    if (m_exportFile.isOpen())
        m_exportFile.close();
    m_exportingCsv = false;
    m_exportDetail = detail;
    emit changed();
    emit eventLogged(detail, level);
}

bool PlaybackBackend::writeFloat32Metadata()
{
    const QFileInfo dataInfo(m_exportFile.fileName());
    const QString jsonPath = QDir(dataInfo.absolutePath()).filePath(dataInfo.completeBaseName() + QStringLiteral(".json"));
    QJsonArray channels;
    for (int id : m_exportChannelIds) {
        QJsonObject channel;
        channel["name"] = QStringLiteral("CH%1").arg(id + 1);
        channel["zeroBasedIndex"] = id;
        channel["unit"] = QStringLiteral("V");
        channels.append(channel);
    }
    QJsonObject metadata;
    metadata["formatVersion"] = 1;
    metadata["sampleType"] = QStringLiteral("float32");
    metadata["byteOrder"] = QStringLiteral("little-endian");
    metadata["dataLayout"] = QStringLiteral("sample-major-interleaved");
    metadata["sampleRate"] = m_sampleRate;
    metadata["channels"] = channels;
    metadata["rangeStartSeconds"] = m_exportStart;
    metadata["rangeEndSeconds"] = m_exportEnd;
    metadata["recordingStartedAt"] = m_startedAt;
    metadata["sampleCount"] = double(m_exportSampleCount);
    metadata["dataFile"] = dataInfo.fileName();
    metadata["dataBytes"] = double(m_exportSampleCount * quint64(m_exportChannelIds.size()) * sizeof(float));

    QFile metadataFile(jsonPath);
    if (!metadataFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return false;
    const QByteArray json = QJsonDocument(metadata).toJson(QJsonDocument::Indented);
    return metadataFile.write(json) == json.size();
}

bool PlaybackBackend::validateFloat32Export(QString *reason) const
{
    const quint64 channelCount = quint64(m_exportChannelIds.size());
    const quint64 expectedBytes = m_exportSampleCount * channelCount * sizeof(float);
    const QFileInfo info(m_exportFile.fileName());
    const quint64 actualBytes = quint64(info.size());
    if (actualBytes != expectedBytes) {
        if (reason)
            *reason = tr("文件大小不匹配：应为 %1 字节，实际为 %2 字节。")
                          .arg(expectedBytes).arg(actualBytes);
        return false;
    }

    QFile file(info.absoluteFilePath());
    if (!file.open(QIODevice::ReadOnly)) {
        if (reason)
            *reason = tr("无法重新读取导出的 Float32 文件。");
        return false;
    }
    QDataStream stream(&file);
    stream.setByteOrder(QDataStream::LittleEndian);
    stream.setFloatingPointPrecision(QDataStream::SinglePrecision);
    const quint64 valueCount = m_exportSampleCount * channelCount;
    for (quint64 index = 0; index < valueCount; ++index) {
        float value = 0.0F;
        stream >> value;
        if (stream.status() != QDataStream::Ok) {
            if (reason)
                *reason = tr("第 %1 个 Float32 数值无法读取。").arg(index);
            return false;
        }
        if (!std::isfinite(value)) {
            if (reason)
                *reason = tr("第 %1 个 Float32 数值为 NaN 或 Inf。").arg(index);
            return false;
        }
    }
    if (!file.atEnd()) {
        if (reason)
            *reason = tr("Float32 文件包含额外字节。");
        return false;
    }
    return true;
}

bool PlaybackBackend::writeMatFileHeader()
{
    QByteArray header(128, ' ');
    const QByteArray description("MATLAB 5.0 MAT-file, Platform: Qt, Created by OscRecorder");
    std::copy(description.cbegin(), description.cend(), header.begin());
    // MATLAB v5: 0x0100 in little-endian order, followed by the IM marker.
    header[124] = '\0';
    header[125] = '\1';
    header[126] = 'I';
    header[127] = 'M';
    return m_exportFile.write(header) == header.size();
}

bool PlaybackBackend::writeMatPadding(quint64 dataBytes)
{
    const quint64 padding = matPaddedBytes(dataBytes) - dataBytes;
    if (!padding)
        return true;
    const QByteArray zeros(int(padding), '\0');
    return m_exportFile.write(zeros) == zeros.size();
}

bool PlaybackBackend::writeMatMatrixHeader(const QString &name, quint32 matrixClass, quint32 dataType,
                                           quint64 rows, quint64 columns, quint64 dataBytes)
{
    const QByteArray nameBytes = name.toLatin1();
    if (rows > 0x7fffffffULL || columns > 0x7fffffffULL || dataBytes > MatMaxElementBytes)
        return false;
    const quint64 nameElementBytes = 8 + matPaddedBytes(quint64(nameBytes.size()));
    const quint64 bodyBytes = 16 + 16 + nameElementBytes + 8 + matPaddedBytes(dataBytes);
    if (bodyBytes > MatMaxElementBytes)
        return false;

    QByteArray fixed;
    QDataStream stream(&fixed, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::LittleEndian);
    stream << MatMiMatrix << quint32(bodyBytes)
           << MatMiUInt32 << quint32(8) << matrixClass << quint32(0)
           << MatMiInt32 << quint32(8) << qint32(rows) << qint32(columns)
           << MatMiInt8 << quint32(nameBytes.size());
    if (stream.status() != QDataStream::Ok || m_exportFile.write(fixed) != fixed.size()
        || m_exportFile.write(nameBytes) != nameBytes.size() || !writeMatPadding(nameBytes.size()))
        return false;
    const QByteArray dataTag = matTag(dataType, quint32(dataBytes));
    return m_exportFile.write(dataTag) == dataTag.size();
}

bool PlaybackBackend::writeMatDoubleScalar(const QString &name, double value)
{
    if (!writeMatMatrixHeader(name, MatMxDoubleClass, MatMiDouble, 1, 1, sizeof(double)))
        return false;
    QByteArray bytes;
    QDataStream stream(&bytes, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::LittleEndian);
    stream << value;
    return stream.status() == QDataStream::Ok && m_exportFile.write(bytes) == bytes.size();
}

bool PlaybackBackend::writeMatCharMatrix(const QString &name, const QStringList &values)
{
    const int rows = values.size();
    int columns = 1;
    for (const QString &value : values)
        columns = qMax(columns, value.size());
    const quint64 byteCount = quint64(rows) * quint64(columns) * sizeof(quint16);
    if (!writeMatMatrixHeader(name, MatMxCharClass, MatMiUInt16, rows, columns, byteCount))
        return false;
    QByteArray bytes;
    QDataStream stream(&bytes, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::LittleEndian);
    // MATLAB stores two-dimensional arrays column-major.
    for (int column = 0; column < columns; ++column)
        for (int row = 0; row < rows; ++row)
            stream << quint16(column < values.at(row).size() ? values.at(row).at(column).unicode() : u' ');
    return stream.status() == QDataStream::Ok && m_exportFile.write(bytes) == bytes.size() && writeMatPadding(byteCount);
}

bool PlaybackBackend::beginMatExport(QString *reason)
{
    if (m_exportExpectedSampleCount > MatMaxElementBytes / sizeof(double)
        || m_exportExpectedSampleCount > MatMaxElementBytes / sizeof(float)) {
        if (reason) *reason = tr("单个 MAT 变量超出 MAT v5 大小限制。");
        return false;
    }
    if (!writeMatFileHeader()
        || !writeMatDoubleScalar(QStringLiteral("sampleRate"), double(m_sampleRate))
        || !writeMatDoubleScalar(QStringLiteral("rangeStartSeconds"), m_exportStart)
        || !writeMatDoubleScalar(QStringLiteral("rangeEndSeconds"), m_exportEnd)) {
        if (reason) *reason = tr("无法写入 MAT 文件头或标量元数据。");
        return false;
    }
    QStringList names, units;
    for (int id : m_exportChannelIds) {
        names.append(QStringLiteral("CH%1").arg(id + 1));
        units.append(QStringLiteral("V"));
    }
    if (!writeMatCharMatrix(QStringLiteral("channelNames"), names)
        || !writeMatCharMatrix(QStringLiteral("channelUnits"), units)
        || !writeMatMatrixHeader(QStringLiteral("time"), MatMxDoubleClass, MatMiDouble,
                                 m_exportExpectedSampleCount, 1, m_exportExpectedSampleCount * sizeof(double))) {
        if (reason) *reason = tr("无法写入 MAT 通道元数据或 time 数组头。");
        return false;
    }
    m_matTimeWritten = 0;
    m_matCurrentChannel = 0;
    m_matChannelSampleCount = 0;
    m_matWritingTime = true;
    m_matChannelHeaderWritten = false;
    return true;
}

bool PlaybackBackend::writeNextMatExportBlock(QString *reason)
{
    constexpr quint64 TimeValuesPerTick = 8192;
    if (m_matWritingTime) {
        const quint64 remaining = m_exportExpectedSampleCount - m_matTimeWritten;
        const quint64 count = qMin(remaining, TimeValuesPerTick);
        QByteArray bytes;
        QDataStream stream(&bytes, QIODevice::WriteOnly);
        stream.setByteOrder(QDataStream::LittleEndian);
        for (quint64 offset = 0; offset < count; ++offset)
            stream << (double(m_exportFirstSample + m_matTimeWritten + offset) / double(m_sampleRate));
        if (stream.status() != QDataStream::Ok || m_exportFile.write(bytes) != bytes.size()) {
            if (reason) *reason = tr("time 数组写入失败。");
            return false;
        }
        m_matTimeWritten += count;
        if (m_matTimeWritten == m_exportExpectedSampleCount) {
            if (!writeMatPadding(m_exportExpectedSampleCount * sizeof(double))) {
                if (reason) *reason = tr("time 数组对齐写入失败。");
                return false;
            }
            m_matWritingTime = false;
            m_exportBlockIndex = 0;
        }
        return true;
    }

    if (m_matCurrentChannel >= m_exportSourceIndexes.size())
        return true;
    if (!m_matChannelHeaderWritten) {
        const int channelId = m_exportChannelIds.at(m_matCurrentChannel);
        if (!writeMatMatrixHeader(QStringLiteral("CH%1").arg(channelId + 1), MatMxSingleClass, MatMiSingle,
                                  m_exportExpectedSampleCount, 1, m_exportExpectedSampleCount * sizeof(float))) {
            if (reason) *reason = tr("通道数组头写入失败。");
            return false;
        }
        m_matChannelHeaderWritten = true;
        m_matChannelSampleCount = 0;
        m_exportBlockIndex = 0;
        return true;
    }

    const quint64 rangeEndSample = m_exportFirstSample + m_exportExpectedSampleCount;
    while (m_exportBlockIndex < m_blocks.size()) {
        const Block &block = m_blocks.at(m_exportBlockIndex++);
        if (block.first + block.count <= m_exportFirstSample || block.first >= rangeEndSample)
            continue;
        QByteArray payload;
        if (!validateBlock(block, &payload)) {
            if (reason) *reason = tr("导出时数据块 CRC 校验失败。");
            return false;
        }
        QDataStream input(payload);
        input.setByteOrder(QDataStream::LittleEndian);
        input.setFloatingPointPrecision(QDataStream::SinglePrecision);
        QByteArray bytes;
        QDataStream output(&bytes, QIODevice::WriteOnly);
        output.setByteOrder(QDataStream::LittleEndian);
        output.setFloatingPointPrecision(QDataStream::SinglePrecision);
        const int sourceIndex = m_exportSourceIndexes.at(m_matCurrentChannel);
        for (quint32 sample = 0; sample < block.count; ++sample) {
            float selected = 0.0F;
            for (int source = 0; source < m_channelCount; ++source) {
                float value = 0.0F;
                input >> value;
                if (source == sourceIndex)
                    selected = value;
            }
            const quint64 sampleIndex = block.first + sample;
            if (sampleIndex < m_exportFirstSample || sampleIndex >= rangeEndSample)
                continue;
            if (!std::isfinite(selected)) {
                if (reason) *reason = tr("CH%1 包含 NaN 或 Inf。").arg(m_exportChannelIds.at(m_matCurrentChannel) + 1);
                return false;
            }
            output << selected;
            ++m_matChannelSampleCount;
        }
        if (input.status() != QDataStream::Ok || output.status() != QDataStream::Ok || m_exportFile.write(bytes) != bytes.size()) {
            if (reason) *reason = tr("通道数组数据写入失败。");
            return false;
        }
        return true;
    }
    if (m_matChannelSampleCount != m_exportExpectedSampleCount || !writeMatPadding(m_exportExpectedSampleCount * sizeof(float))) {
        if (reason) *reason = tr("通道样本数或对齐字节不正确。");
        return false;
    }
    ++m_matCurrentChannel;
    m_matChannelHeaderWritten = false;
    return true;
}

bool PlaybackBackend::validateMatExport(QString *reason) const
{
    QFile file(m_exportFile.fileName());
    if (!file.open(QIODevice::ReadOnly) || file.size() < 128) {
        if (reason) *reason = tr("无法重新读取 MAT 文件头。");
        return false;
    }
    const QByteArray header = file.read(128);
    if (header.size() != 128 || header.mid(126, 2) != QByteArrayLiteral("IM")) {
        if (reason) *reason = tr("MAT v5 文件头或字节序标记无效。");
        return false;
    }
    struct MatVariable {
        quint32 type = 0;
        quint64 rows = 0, columns = 0, bytes = 0;
        qint64 dataOffset = 0;
    };
    QMap<QString, MatVariable> variables;
    QDataStream stream(&file);
    stream.setByteOrder(QDataStream::LittleEndian);
    while (!file.atEnd()) {
        quint32 type = 0, matrixBytes = 0;
        stream >> type >> matrixBytes;
        if (stream.status() != QDataStream::Ok || type != MatMiMatrix || matrixBytes == 0 || file.pos() + matrixBytes > file.size()) {
            if (reason) *reason = tr("MAT 变量元素结构无效。");
            return false;
        }
        const qint64 matrixEnd = file.pos() + matrixBytes;
        quint32 elementType = 0, elementBytes = 0, flags = 0, unused = 0;
        qint32 rows = 0, columns = 0;
        stream >> elementType >> elementBytes >> flags >> unused
               >> elementType >> elementBytes >> rows >> columns
               >> elementType >> elementBytes;
        if (stream.status() != QDataStream::Ok || rows < 0 || columns < 0 || elementType != MatMiInt8) {
            if (reason) *reason = tr("MAT 变量维度或名称无效。");
            return false;
        }
        const QByteArray name = file.read(elementBytes);
        if (name.size() != int(elementBytes) || !file.seek(file.pos() + qint64(matPaddedBytes(elementBytes) - elementBytes))) {
            if (reason) *reason = tr("MAT 变量名称无法读取。");
            return false;
        }
        quint32 dataType = 0, dataBytes = 0;
        stream >> dataType >> dataBytes;
        if (stream.status() != QDataStream::Ok || file.pos() + dataBytes > matrixEnd) {
            if (reason) *reason = tr("MAT 变量数据元素无效。");
            return false;
        }
        variables.insert(QString::fromLatin1(name), { dataType, quint64(rows), quint64(columns), dataBytes, file.pos() });
        if (!file.seek(matrixEnd)) {
            if (reason) *reason = tr("MAT 变量定位失败。");
            return false;
        }
    }
    const auto has = [&variables](const QString &name, quint32 type, quint64 rows, quint64 columns, quint64 bytes) {
        const MatVariable value = variables.value(name);
        return value.type == type && value.rows == rows && value.columns == columns && value.bytes == bytes;
    };
    if (!has(QStringLiteral("time"), MatMiDouble, m_exportExpectedSampleCount, 1, m_exportExpectedSampleCount * sizeof(double))
        || !has(QStringLiteral("sampleRate"), MatMiDouble, 1, 1, sizeof(double))
        || !has(QStringLiteral("rangeStartSeconds"), MatMiDouble, 1, 1, sizeof(double))
        || !has(QStringLiteral("rangeEndSeconds"), MatMiDouble, 1, 1, sizeof(double))
        || !variables.contains(QStringLiteral("channelNames")) || !variables.contains(QStringLiteral("channelUnits"))) {
        if (reason) *reason = tr("MAT 必需变量或维度校验失败。");
        return false;
    }
    for (int id : m_exportChannelIds) {
        if (!has(QStringLiteral("CH%1").arg(id + 1), MatMiSingle, m_exportExpectedSampleCount, 1,
                 m_exportExpectedSampleCount * sizeof(float))) {
            if (reason) *reason = tr("MAT 通道 CH%1 变量校验失败。").arg(id + 1);
            return false;
        }
    }
    const MatVariable names = variables.value(QStringLiteral("channelNames"));
    const MatVariable units = variables.value(QStringLiteral("channelUnits"));
    if (names.type != MatMiUInt16 || units.type != MatMiUInt16
        || names.rows != quint64(m_exportChannelIds.size()) || units.rows != quint64(m_exportChannelIds.size())
        || names.columns == 0 || units.columns == 0
        || names.bytes != names.rows * names.columns * sizeof(quint16)
        || units.bytes != units.rows * units.columns * sizeof(quint16)) {
        if (reason) *reason = tr("MAT 通道名称或单位矩阵校验失败。");
        return false;
    }
    const auto readDouble = [&file](qint64 offset, double *value) {
        if (!file.seek(offset)) return false;
        QDataStream scalar(&file);
        scalar.setByteOrder(QDataStream::LittleEndian);
        scalar >> *value;
        return scalar.status() == QDataStream::Ok;
    };
    double sampleRate = 0.0, rangeStart = 0.0, rangeEnd = 0.0;
    if (!readDouble(variables.value(QStringLiteral("sampleRate")).dataOffset, &sampleRate)
        || !readDouble(variables.value(QStringLiteral("rangeStartSeconds")).dataOffset, &rangeStart)
        || !readDouble(variables.value(QStringLiteral("rangeEndSeconds")).dataOffset, &rangeEnd)
        || sampleRate != double(m_sampleRate) || std::abs(rangeStart - m_exportStart) > 1e-12
        || std::abs(rangeEnd - m_exportEnd) > 1e-12) {
        if (reason) *reason = tr("MAT 标量元数据数值校验失败。");
        return false;
    }
    if (m_exportExpectedSampleCount > 0) {
        const MatVariable time = variables.value(QStringLiteral("time"));
        double firstTime = 0.0, lastTime = 0.0;
        if (!readDouble(time.dataOffset, &firstTime)
            || !readDouble(time.dataOffset + qint64((m_exportExpectedSampleCount - 1) * sizeof(double)), &lastTime)
            || std::abs(firstTime - double(m_exportFirstSample) / double(m_sampleRate)) > 1e-12
            || std::abs(lastTime - double(m_exportFirstSample + m_exportExpectedSampleCount - 1) / double(m_sampleRate)) > 1e-12) {
            if (reason) *reason = tr("MAT time 数组数值校验失败。");
            return false;
        }
    }
    return true;
}

void PlaybackBackend::writeNextDataExportBlock()
{
    if (m_exportFormat == QStringLiteral("mat")) {
        QString matError;
        if (!writeNextMatExportBlock(&matError)) {
            finishDataExport(tr("MAT 导出失败：%1").arg(matError), "ERROR");
            return;
        }
        if (m_matWritingTime || m_matCurrentChannel < m_exportSourceIndexes.size()) {
            m_exportDetail = m_matWritingTime
                ? tr("正在导出 MAT 时间数组（%1/%2）…").arg(m_matTimeWritten).arg(m_exportExpectedSampleCount)
                : tr("正在导出 MAT 通道（%1/%2）…").arg(m_matCurrentChannel + 1).arg(m_exportSourceIndexes.size());
            emit changed();
            return;
        }
        const QString dataPath = m_exportFile.fileName();
        if (!m_exportFile.flush()) {
            finishDataExport(tr("MAT 文件刷新失败。"), "ERROR");
            return;
        }
        m_exportFile.close();
        if (!validateMatExport(&matError)) {
            finishDataExport(tr("MAT 导出校验失败：%1").arg(matError), "ERROR");
            return;
        }
        m_exportSampleCount = m_exportExpectedSampleCount;
        finishDataExport(tr("MAT 导出完成（MAT v5 已校验）：%1").arg(dataPath), "INFO");
        return;
    }
    while (m_exportBlockIndex < m_blocks.size()) {
        const Block &block = m_blocks.at(m_exportBlockIndex++);
        const double blockEnd = block.start + double(block.count) / m_sampleRate;
        if (blockEnd < m_exportStart || block.start > m_exportEnd)
            continue;

        QByteArray payload;
        if (!validateBlock(block, &payload)) {
            finishDataExport(tr("导出时数据块校验失败。"), "ERROR");
            return;
        }
        QDataStream stream(payload);
        stream.setByteOrder(QDataStream::LittleEndian);
        stream.setFloatingPointPrecision(QDataStream::SinglePrecision);
        QVector<float> values(m_channelCount);
        QByteArray rows;
        QDataStream floatStream(&rows, QIODevice::WriteOnly);
        floatStream.setByteOrder(QDataStream::LittleEndian);
        floatStream.setFloatingPointPrecision(QDataStream::SinglePrecision);
        for (quint32 sample = 0; sample < block.count; ++sample) {
            const double time = block.start + double(sample) / m_sampleRate;
            for (int source = 0; source < m_channelCount; ++source)
                stream >> values[source];
            if (stream.status() != QDataStream::Ok) {
                finishDataExport(tr("导出时读取采样数据失败。"), "ERROR");
                return;
            }
            if (time < m_exportStart || time > m_exportEnd)
                continue;
            if (m_exportFormat == QStringLiteral("csv")) {
                rows += QByteArray::number(time, 'f', 9);
                for (int source : m_exportSourceIndexes) {
                    rows += ',';
                    rows += QByteArray::number(values[source], 'g', 9);
                }
                rows += '\n';
            } else {
                for (int source : m_exportSourceIndexes)
                    floatStream << values[source];
            }
            ++m_exportSampleCount;
        }
        if (m_exportFormat == QStringLiteral("float32") && floatStream.status() != QDataStream::Ok) {
            finishDataExport(tr("Float32 文件写入缓冲失败。"), "ERROR");
            return;
        }
        if (m_exportFile.write(rows) != rows.size()) {
            finishDataExport(tr("导出文件写入失败。"), "ERROR");
            return;
        }
        m_exportFile.flush();
        m_exportDetail = (m_exportFormat == QStringLiteral("csv") ? tr("正在导出 CSV（%1/%2 块）…") : tr("正在导出 Float32（%1/%2 块）…")).arg(m_exportBlockIndex).arg(m_blocks.size());
        emit changed();
        return;
    }
    if (m_exportFormat == QStringLiteral("float32")) {
        const QString dataPath = m_exportFile.fileName();
        if (!m_exportFile.flush()) {
            finishDataExport(tr("Float32 二进制文件刷新失败。"), "ERROR");
            return;
        }
        m_exportFile.close();
        QString validationError;
        if (!validateFloat32Export(&validationError)) {
            finishDataExport(tr("Float32 导出校验失败：%1").arg(validationError), "ERROR");
            return;
        }
        if (!writeFloat32Metadata()) {
            finishDataExport(tr("Float32 数据校验通过，但 JSON 元数据写入失败。"), "ERROR");
            return;
        }
        finishDataExport(tr("Float32+JSON 导出完成（已校验）：%1").arg(dataPath), "INFO");
        return;
    }
    finishDataExport(tr("CSV 导出完成：%1").arg(m_exportFile.fileName()), "INFO");
}

void PlaybackBackend::loadWindow()
{
    m_frames.clear();
    for (int id : m_displayIds) { QVariantMap frame; frame["id"] = id; frame["name"] = QStringLiteral("CH%1").arg(id + 1); frame["points"] = QVariantList(); m_frames.append(frame); }
    if (m_status != "ready" || m_displayIds.isEmpty()) { emit changed(); return; }
    const double end = m_viewStart + m_viewDuration;
    QList<QVariantList> points(m_displayIds.size());
    for (const Block &block : m_blocks) {
        const double blockEnd = block.start + double(block.count) / m_sampleRate;
        if (blockEnd < m_viewStart || block.start > end) continue;
        QByteArray payload; if (!validateBlock(block, &payload)) return;
        QDataStream stream(payload); stream.setByteOrder(QDataStream::LittleEndian); stream.setFloatingPointPrecision(QDataStream::SinglePrecision);
        for (quint32 sample = 0; sample < block.count; ++sample) {
            const double time = block.start + double(sample) / m_sampleRate;
            for (int source = 0; source < m_channelCount; ++source) {
                float value = 0; stream >> value; const int target = m_displayIds.indexOf(m_channelIds[source]);
                if (target >= 0 && time >= m_viewStart && time <= end) { QVariantMap point; point["t"] = time; point["v"] = value; points[target].append(point); }
            }
        }
    }
    for (int index = 0; index < m_frames.size(); ++index) { QVariantMap frame = m_frames[index].toMap(); frame["points"] = points[index]; m_frames[index] = frame; }
    emit changed();
}
