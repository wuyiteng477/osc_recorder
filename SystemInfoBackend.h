#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQmlIntegration/qqmlintegration.h>

// Cross-platform application diagnostics.  Hardware-specific RK3588 probes
// can be added here later without changing the settings-page contract.
class SystemInfoBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString softwareVersion READ softwareVersion CONSTANT)
    Q_PROPERTY(QString buildInfo READ buildInfo CONSTANT)
    Q_PROPERTY(QString platformName READ platformName CONSTANT)
    Q_PROPERTY(QString dataSourceType READ dataSourceType CONSTANT)
    Q_PROPERTY(QString configurationPath READ configurationPath CONSTANT)
    Q_PROPERTY(QString logDirectory READ logDirectory CONSTANT)
    Q_PROPERTY(QString logFilePath READ logFilePath CONSTANT)

public:
    explicit SystemInfoBackend(QObject *parent = nullptr);
    QString softwareVersion() const; QString buildInfo() const; QString platformName() const;
    QString dataSourceType() const; QString configurationPath() const; QString logDirectory() const; QString logFilePath() const;
    Q_INVOKABLE void appendLog(const QString &line);
    Q_INVOKABLE void writeConfiguration(const QVariantMap &configuration);
    Q_INVOKABLE bool openLogDirectory() const;
    Q_INVOKABLE QString exportDiagnostics(const QVariantMap &state);

signals:
    void diagnosticExported(const QString &path);

private:
    void ensureDirectories() const;
    QString m_configPath, m_logDirectory, m_logFile;
};
