#pragma once

#include <QObject>
#include <QFile>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQmlIntegration/qqmlintegration.h>

class PlaybackBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString detail READ detail NOTIFY changed)
    Q_PROPERTY(QString sessionDirectory READ sessionDirectory NOTIFY changed)
    Q_PROPERTY(QString startedAt READ startedAt NOTIFY changed)
    Q_PROPERTY(QString finishedAt READ finishedAt NOTIFY changed)
    Q_PROPERTY(int sampleRate READ sampleRate NOTIFY changed)
    Q_PROPERTY(double durationSeconds READ durationSeconds NOTIFY changed)
    Q_PROPERTY(qint64 dataBytes READ dataBytes NOTIFY changed)
    Q_PROPERTY(quint64 gapCount READ gapCount NOTIFY changed)
    Q_PROPERTY(QVariantList channels READ channels NOTIFY changed)
    Q_PROPERTY(int displayedChannelCount READ displayedChannelCount NOTIFY changed)
    Q_PROPERTY(QVariantList frames READ frames NOTIFY changed)
    Q_PROPERTY(double viewStartSeconds READ viewStartSeconds NOTIFY changed)
    Q_PROPERTY(double viewDurationSeconds READ viewDurationSeconds NOTIFY changed)
    Q_PROPERTY(bool exportingData READ exportingData NOTIFY changed)
    Q_PROPERTY(QString exportDetail READ exportDetail NOTIFY changed)

public:
    explicit PlaybackBackend(QObject *parent = nullptr);
    QString status() const; QString detail() const; QString sessionDirectory() const;
    QString startedAt() const; QString finishedAt() const; int sampleRate() const;
    double durationSeconds() const; qint64 dataBytes() const; quint64 gapCount() const;
    QVariantList channels() const; QVariantList frames() const;
    int displayedChannelCount() const;
    double viewStartSeconds() const; double viewDurationSeconds() const;
    bool exportingData() const; QString exportDetail() const;

    Q_INVOKABLE bool loadSessionUrl(const QUrl &url);
    Q_INVOKABLE bool loadSessionPath(const QString &path);
    Q_INVOKABLE void setDisplayChannels(const QVariantList &zeroBasedIds);
    Q_INVOKABLE bool toggleDisplayChannel(int zeroBasedId, bool selected);
    Q_INVOKABLE void setView(double startSeconds, double durationSeconds);
    Q_INVOKABLE void moveView(double seconds);
    Q_INVOKABLE void resetView();
    Q_INVOKABLE QVariantMap measureWindow(int zeroBasedChannelId, double startSeconds, double endSeconds);
    Q_INVOKABLE QUrl suggestedExportUrl(const QString &rangeTag, const QString &format) const;
    Q_INVOKABLE bool beginDataExport(const QUrl &outputUrl, bool wholeRecord, bool allRecordedChannels, const QString &format);

signals:
    void changed();
    void eventLogged(const QString &message, const QString &level);

private:
    struct Block { double start = 0; quint64 first = 0; quint32 count = 0; qint64 offset = 0; quint32 bytes = 0; quint32 crc = 0; };
    bool fail(const QString &message);
    bool parseAndValidate(const QString &directory, const QString &sessionPath);
    bool validateBlock(const Block &block, QByteArray *payload = nullptr);
    void loadWindow();
    void finishDataExport(const QString &detail, const QString &level);
    bool writeFloat32Metadata();
    bool validateFloat32Export(QString *reason) const;
    bool beginMatExport(QString *reason);
    bool writeNextMatExportBlock(QString *reason);
    bool writeMatFileHeader();
    bool writeMatMatrixHeader(const QString &name, quint32 matrixClass, quint32 dataType, quint64 rows, quint64 columns, quint64 dataBytes);
    bool writeMatDoubleScalar(const QString &name, double value);
    bool writeMatCharMatrix(const QString &name, const QStringList &values);
    bool writeMatPadding(quint64 dataBytes);
    bool validateMatExport(QString *reason) const;
    quint32 crc32(const QByteArray &data) const;
private slots:
    void writeNextDataExportBlock();

private:
    QString m_status = QStringLiteral("empty"), m_detail, m_sessionDirectory, m_startedAt, m_finishedAt, m_dataPath;
    int m_sampleRate = 0, m_channelCount = 0;
    double m_durationSeconds = 0, m_viewStart = 0, m_viewDuration = .1;
    qint64 m_dataBytes = 0;
    quint64 m_gapCount = 0, m_sampleCount = 0;
    QList<int> m_channelIds;
    QList<Block> m_blocks;
    QVariantList m_channels, m_frames;
    QList<int> m_displayIds;
    QFile m_exportFile;
    QTimer m_exportTimer;
    QList<int> m_exportChannelIds, m_exportSourceIndexes;
    int m_exportBlockIndex = 0;
    double m_exportStart = 0, m_exportEnd = 0;
    bool m_exportingCsv = false;
    QString m_exportDetail;
    QString m_exportFormat;
    quint64 m_exportSampleCount = 0;
    quint64 m_exportFirstSample = 0, m_exportExpectedSampleCount = 0;
    quint64 m_matTimeWritten = 0, m_matChannelSampleCount = 0;
    int m_matCurrentChannel = 0;
    bool m_matWritingTime = false, m_matChannelHeaderWritten = false;
};
