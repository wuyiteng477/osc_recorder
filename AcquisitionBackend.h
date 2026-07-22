#pragma once

#include <QObject>
#include <QVariantList>
#include <QtQmlIntegration/qqmlintegration.h>

// This class is the single source of supported acquisition-rate selections.
// Replace the table when the installed board firmware reports its real limits.
class AcquisitionBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantList boardCapabilities READ boardCapabilities CONSTANT)
    Q_PROPERTY(QVariantList simulationStressRates READ simulationStressRates CONSTANT)
    Q_PROPERTY(int displayRefreshRate READ displayRefreshRate CONSTANT)

public:
    explicit AcquisitionBackend(QObject *parent = nullptr);

    QVariantList boardCapabilities() const;
    QVariantList simulationStressRates() const;
    int displayRefreshRate() const;

    Q_INVOKABLE QVariantList ratesForBoard(int boardIndex) const;
    Q_INVOKABLE bool supportsHardwareRate(int boardIndex, int sampleRate) const;
    Q_INVOKABLE bool supportsSimulationStressRate(int sampleRate) const;

private:
    QVariantList m_boardCapabilities;
    QVariantList m_simulationStressRates;
};
