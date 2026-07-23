#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QFile>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QtQmlIntegration/qqmlintegration.h>

class RecorderBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString saveDirectory READ saveDirectory NOTIFY saveDirectoryChanged)
    Q_PROPERTY(QUrl saveDirectoryUrl READ saveDirectoryUrl NOTIFY saveDirectoryChanged)
    Q_PROPERTY(QString sessionDirectory READ sessionDirectory NOTIFY recordingStateChanged)
    Q_PROPERTY(QString currentFileName READ currentFileName NOTIFY recordingStateChanged)
    Q_PROPERTY(QString status READ status NOTIFY recordingStateChanged)
    Q_PROPERTY(QString statusDetail READ statusDetail NOTIFY recordingStateChanged)
    Q_PROPERTY(QString createdAt READ createdAt NOTIFY recordingStateChanged)
    Q_PROPERTY(QString finishedAt READ finishedAt NOTIFY recordingStateChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY recordingStateChanged)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY storageChanged)
    Q_PROPERTY(qint64 availableBytes READ availableBytes NOTIFY storageChanged)
    Q_PROPERTY(qint64 theoreticalBytesPerSecond READ theoreticalBytesPerSecond NOTIFY recordingStateChanged)
    Q_PROPERTY(qint64 simulatedFileBytes READ simulatedFileBytes NOTIFY recordingStateChanged)
    Q_PROPERTY(qint64 recordedMilliseconds READ recordedMilliseconds NOTIFY recordingStateChanged)

public:
    explicit RecorderBackend(QObject *parent = nullptr);
    QString saveDirectory() const; QUrl saveDirectoryUrl() const; QString sessionDirectory() const; QString currentFileName() const;
    QString status() const; QString statusDetail() const; QString createdAt() const; QString finishedAt() const; bool recording() const;
    qint64 totalBytes() const; qint64 availableBytes() const; qint64 theoreticalBytesPerSecond() const; qint64 simulatedFileBytes() const; qint64 recordedMilliseconds() const;
    Q_INVOKABLE void setSaveDirectory(const QString &localPath);
    Q_INVOKABLE void setSaveDirectoryUrl(const QUrl &directoryUrl);
    Q_INVOKABLE void setRecordingParameters(int sampleRate, int enabledChannels);
    Q_INVOKABLE void refreshStorage();
    Q_INVOKABLE bool startRecording(int sampleRate, const QVariantList &channelIds, const QString &acquisitionMode, bool acquisitionRunning);
    void enqueueRawSampleBlock(double startTimeSeconds, const QByteArray &payload, bool hasGap);
    Q_INVOKABLE void stopRecording();
signals:
    void saveDirectoryChanged(); void storageChanged(); void recordingStateChanged(); void eventLogged(const QString &message, const QString &level);
private slots:
    void flushPendingBlocks();
private:
    struct Block { double startTime = 0; quint64 firstSample = 0; quint32 count = 0; QByteArray payload; bool hasGap = false; };
    bool prepareDirectory(QString *reason); bool writeBlock(const Block &block); bool validateIndex(QString *reason); quint32 crc32(const QByteArray &data) const; void writeSessionMetadata(); void setStatus(const QString &value, const QString &detail = {}); void writeLog(const QString &line);
    QString m_saveDirectory, m_sessionDirectory, m_temporarySessionDirectory, m_currentFileName, m_status = QStringLiteral("not_ready"), m_statusDetail, m_createdAt, m_finishedAt, m_acquisitionMode;
    qint64 m_totalBytes = 0, m_availableBytes = 0, m_theoreticalBytesPerSecond = 0, m_simulatedFileBytes = 0, m_recordedMilliseconds = 0;
    int m_sampleRate = 0; quint64 m_nextSample = 0; quint64 m_gapCount = 0; double m_firstBlockTime = 0; bool m_hasFirstBlockTime = false; QList<int> m_channelIds; QList<Block> m_pendingBlocks;
    QElapsedTimer m_recordingClock; QFile m_dataFile, m_indexFile, m_logFile; QTimer m_writeTimer;
};
