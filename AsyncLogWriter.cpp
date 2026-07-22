#include "AsyncLogWriter.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QMutex>
#include <QSet>
#include <QStringList>
#include <QThread>
#include <QTimer>
#include <algorithm>

namespace {
constexpr qint64 MaximumLogFileBytes = 10LL * 1024 * 1024;
constexpr qint64 MaximumLogDirectoryBytes = 200LL * 1024 * 1024;
constexpr qint64 MaximumLogAgeDays = 14;

class Writer final : public QObject
{
public:
    void initialize()
    {
        m_timer = new QTimer(this);
        m_timer->setInterval(250);
        connect(m_timer, &QTimer::timeout, this, [this] { flush(); });
    }

    void enqueue(const QString &path, const QString &line, bool managed)
    {
        if (path.isEmpty() || line.isEmpty()) return;
        m_pending[path].append(line.endsWith('\n') ? line : line + '\n');
        if (managed) m_managedDirectories.insert(QFileInfo(path).absolutePath());
        if (m_timer && !m_timer->isActive()) m_timer->start();
    }

    void cleanup(const QString &directory)
    {
        if (directory.isEmpty()) return;
        m_managedDirectories.insert(directory);
        cleanupDirectory(directory);
    }

    void flushPath(const QString &path)
    {
        flush(path);
    }

    void flush()
    {
        flush(QString());
    }

private:
    void flush(const QString &onlyPath)
    {
        const auto pending = m_pending;
        for (auto it = pending.cbegin(); it != pending.cend(); ++it) {
            if (!onlyPath.isEmpty() && it.key() != onlyPath) continue;
            const QStringList lines = m_pending.take(it.key());
            if (lines.isEmpty()) continue;
            const QFileInfo info(it.key());
            QDir().mkpath(info.absolutePath());
            QByteArray bytes;
            for (const QString &line : lines) bytes += line.toUtf8();
            rotateIfNeeded(it.key(), bytes.size());
            QFile file(it.key());
            if (file.open(QIODevice::WriteOnly | QIODevice::Append)) file.write(bytes);
        }
        if (onlyPath.isEmpty()) {
            for (const QString &directory : std::as_const(m_managedDirectories)) cleanupDirectory(directory);
            if (m_pending.isEmpty() && m_timer) m_timer->stop();
        }
    }

    void rotateIfNeeded(const QString &path, qint64 incomingBytes)
    {
        const QFileInfo active(path);
        if (!active.exists() || active.size() + incomingBytes <= MaximumLogFileBytes) return;
        const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss_zzz");
        const QString base = active.completeBaseName();
        const QString suffix = active.suffix();
        const QString archived = QDir(active.absolutePath()).filePath(base + '_' + stamp + '.' + suffix);
        QFile::rename(path, archived);
    }

    void cleanupDirectory(const QString &directory)
    {
        QDir dir(directory);
        if (!dir.exists()) return;
        struct Entry { QFileInfo info; };
        QList<Entry> entries;
        qint64 total = 0;
        const QDateTime expiry = QDateTime::currentDateTime().addDays(-MaximumLogAgeDays);
        const QFileInfoList files = dir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot, QDir::Time);
        for (const QFileInfo &file : files) {
            if (file.lastModified() < expiry) { QFile::remove(file.absoluteFilePath()); continue; }
            entries.append({file});
            total += file.size();
        }
        std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) { return a.info.lastModified() < b.info.lastModified(); });
        for (const Entry &entry : std::as_const(entries)) {
            if (total <= MaximumLogDirectoryBytes) break;
            if (QFile::remove(entry.info.absoluteFilePath())) total -= entry.info.size();
        }
    }

    QHash<QString, QStringList> m_pending;
    QSet<QString> m_managedDirectories;
    QTimer *m_timer = nullptr;
};

struct Service {
    QThread thread;
    Writer *writer = nullptr;
    Service()
    {
        writer = new Writer;
        writer->moveToThread(&thread);
        thread.start();
        QMetaObject::invokeMethod(writer, [this] { writer->initialize(); }, Qt::BlockingQueuedConnection);
    }
    ~Service()
    {
        QMetaObject::invokeMethod(writer, [this] { writer->flush(); }, Qt::BlockingQueuedConnection);
        thread.quit();
        thread.wait();
        delete writer;
    }
};

Service &service()
{
    static Service instance;
    return instance;
}

void enqueue(const QString &path, const QString &line, bool managed)
{
    auto &instance = service();
    QMetaObject::invokeMethod(instance.writer, [writer = instance.writer, path, line, managed] { writer->enqueue(path, line, managed); }, Qt::QueuedConnection);
}
}

namespace AsyncLogWriter {
void appendGlobal(const QString &filePath, const QString &line) { enqueue(filePath, line, true); }
void appendRecording(const QString &filePath, const QString &line) { enqueue(filePath, line, false); }
void cleanupGlobalDirectory(const QString &directory)
{
    auto &instance = service();
    QMetaObject::invokeMethod(instance.writer, [writer = instance.writer, directory] { writer->cleanup(directory); }, Qt::QueuedConnection);
}
void flushRecording(const QString &filePath)
{
    auto &instance = service();
    QMetaObject::invokeMethod(instance.writer, [writer = instance.writer, filePath] { writer->flushPath(filePath); }, Qt::BlockingQueuedConnection);
}
void shutdown() { }
}
