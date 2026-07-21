#include "PlaybackBackend.h"

#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>

namespace {
constexpr quint32 FileMagic = 0x4f534352;
constexpr quint32 BlockMagic = 0x424c4b31;
constexpr quint32 BlockCommitted = 0x434d5431;
constexpr int BlockHeaderBytes = 36;
}

PlaybackBackend::PlaybackBackend(QObject *parent) : QObject(parent) {}
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
double PlaybackBackend::viewStartSeconds() const { return m_viewStart; }
double PlaybackBackend::viewDurationSeconds() const { return m_viewDuration; }

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
        if (!validateBlock(block)) return false;
        expectedFirst += block.count; expectedEnd = block.offset + BlockHeaderBytes + block.bytes; m_blocks.append(block);
    }
    if (m_blocks.isEmpty() || expectedFirst != m_sampleCount || QFileInfo(m_dataPath).size() != expectedEnd) return fail(tr("索引记录与数据文件大小或样本数不一致。"));
    m_displayIds = m_channelIds.mid(0, 8); m_viewDuration = qMin(qMax(.001, m_durationSeconds), .1); m_viewStart = qMax(0.0, m_durationSeconds - m_viewDuration);
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
    if (next.isEmpty() && !m_channelIds.isEmpty()) next.append(m_channelIds.first());
    m_displayIds = next;
    for (int index = 0; index < m_channels.size(); ++index) {
        QVariantMap channel = m_channels[index].toMap();
        channel["enabled"] = m_displayIds.contains(channel.value("id").toInt());
        m_channels[index] = channel;
    }
    loadWindow();
}

void PlaybackBackend::setView(double start, double duration)
{
    if (m_status != "ready") return; m_viewDuration = qBound(.001, duration, qMax(.001, m_durationSeconds)); m_viewStart = qBound(0.0, start, qMax(0.0, m_durationSeconds - m_viewDuration)); loadWindow();
}
void PlaybackBackend::moveView(double seconds) { setView(m_viewStart + seconds, m_viewDuration); }
void PlaybackBackend::resetView() { setView(qMax(0.0, m_durationSeconds - m_viewDuration), m_viewDuration); }

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
