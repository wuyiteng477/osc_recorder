#include "SystemInfoBackend.h"
#include "AsyncLogWriter.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUrl>

SystemInfoBackend::SystemInfoBackend(QObject *parent) : QObject(parent)
{
    const QString configDirectory = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    const QString dataDirectory = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    m_configPath = QDir(configDirectory).filePath("runtime_config.json");
    m_logDirectory = QDir(dataDirectory).filePath("logs");
    m_logFile = QDir(m_logDirectory).filePath("application.log");
    ensureDirectories();
    // Cleanup is queued before normal application activity begins.  It keeps
    // the log folder bounded without delaying the GUI startup path.
    AsyncLogWriter::cleanupGlobalDirectory(m_logDirectory);
}

void SystemInfoBackend::ensureDirectories() const { QDir().mkpath(QFileInfo(m_configPath).absolutePath()); QDir().mkpath(m_logDirectory); }
QString SystemInfoBackend::softwareVersion() const { return QCoreApplication::applicationVersion(); }
QString SystemInfoBackend::buildInfo() const { return QStringLiteral("Qt %1 · C++20").arg(QString::fromLatin1(QT_VERSION_STR)); }
QString SystemInfoBackend::platformName() const { return QSysInfo::prettyProductName() + " · " + QSysInfo::currentCpuArchitecture(); }
QString SystemInfoBackend::dataSourceType() const { return tr("模拟数据源（实时缓存）"); }
QString SystemInfoBackend::configurationPath() const { return m_configPath; }
QString SystemInfoBackend::logDirectory() const { return m_logDirectory; }
QString SystemInfoBackend::logFilePath() const { return m_logFile; }

void SystemInfoBackend::appendLog(const QString &line)
{
    ensureDirectories();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const qint64 previous = m_recentLogTimes.value(line, 0);
    // Suppress identical high-frequency messages while keeping state changes
    // and errors intact.  The UI still receives the original user action log.
    if (previous && now - previous < 1000) return;
    m_recentLogTimes.insert(line, now);
    if (m_recentLogTimes.size() > 256) m_recentLogTimes.clear();
    AsyncLogWriter::appendGlobal(m_logFile, QDateTime::currentDateTime().toString(Qt::ISODateWithMs) + " " + line);
}

void SystemInfoBackend::writeConfiguration(const QVariantMap &configuration)
{
    ensureDirectories();
    QFile file(m_configPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(QJsonDocument::fromVariant(configuration).toJson(QJsonDocument::Indented));
}

bool SystemInfoBackend::openLogDirectory() const { ensureDirectories(); return QDesktopServices::openUrl(QUrl::fromLocalFile(m_logDirectory)); }

QString SystemInfoBackend::exportDiagnostics(const QVariantMap &state)
{
    ensureDirectories();
    const QString path = QDir(m_logDirectory).filePath("diagnostics_" + QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss_zzz") + ".json");
    QVariantMap report = state;
    report.insert("softwareVersion", softwareVersion()); report.insert("buildInfo", buildInfo());
    report.insert("platform", platformName()); report.insert("dataSource", dataSourceType());
    report.insert("configurationPath", m_configPath); report.insert("logFile", m_logFile);
    report.insert("exportedAt", QDateTime::currentDateTime().toString(Qt::ISODateWithMs));
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) return {};
    file.write(QJsonDocument::fromVariant(report).toJson(QJsonDocument::Indented));
    emit diagnosticExported(path);
    return path;
}
