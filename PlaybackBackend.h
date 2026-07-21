#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantList>
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
    Q_PROPERTY(QVariantList frames READ frames NOTIFY changed)
    Q_PROPERTY(double viewStartSeconds READ viewStartSeconds NOTIFY changed)
    Q_PROPERTY(double viewDurationSeconds READ viewDurationSeconds NOTIFY changed)

public:
    explicit PlaybackBackend(QObject *parent = nullptr);
    QString status() const; QString detail() const; QString sessionDirectory() const;
    QString startedAt() const; QString finishedAt() const; int sampleRate() const;
    double durationSeconds() const; qint64 dataBytes() const; quint64 gapCount() const;
    QVariantList channels() const; QVariantList frames() const;
    double viewStartSeconds() const; double viewDurationSeconds() const;

    Q_INVOKABLE bool loadSessionUrl(const QUrl &url);
    Q_INVOKABLE bool loadSessionPath(const QString &path);
    Q_INVOKABLE void setDisplayChannels(const QVariantList &zeroBasedIds);
    Q_INVOKABLE void setView(double startSeconds, double durationSeconds);
    Q_INVOKABLE void moveView(double seconds);
    Q_INVOKABLE void resetView();

signals:
    void changed();
    void eventLogged(const QString &message, const QString &level);

private:
    struct Block { double start = 0; quint64 first = 0; quint32 count = 0; qint64 offset = 0; quint32 bytes = 0; quint32 crc = 0; };
    bool fail(const QString &message);
    bool parseAndValidate(const QString &directory, const QString &sessionPath);
    bool validateBlock(const Block &block, QByteArray *payload = nullptr);
    void loadWindow();
    quint32 crc32(const QByteArray &data) const;

    QString m_status = QStringLiteral("empty"), m_detail, m_sessionDirectory, m_startedAt, m_finishedAt, m_dataPath;
    int m_sampleRate = 0, m_channelCount = 0;
    double m_durationSeconds = 0, m_viewStart = 0, m_viewDuration = .1;
    qint64 m_dataBytes = 0;
    quint64 m_gapCount = 0, m_sampleCount = 0;
    QList<int> m_channelIds;
    QList<Block> m_blocks;
    QVariantList m_channels, m_frames;
    QList<int> m_displayIds;
};
