#include "SystemInfoBackend.h"

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
    QFile file(m_logFile);
    if (file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        file.write((QDateTime::currentDateTime().toString(Qt::ISODateWithMs) + " " + line + "\n").toUtf8());
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
