#include "AcquisitionBackend.h"

#include <QVariantMap>

AcquisitionBackend::AcquisitionBackend(QObject *parent) : QObject(parent)
{
    // Conservative capability table used until the physical board reports its
    // firmware capabilities.  Deliberately no unverified 5 M/50 M S/s tiers.
    const QVariantList baseRates { 1000, 5000, 10000, 20000, 50000 };
    for (int board = 0; board < 8; ++board) {
        QVariantMap item;
        item.insert("boardIndex", board);
        item.insert("name", tr("板卡 %1").arg(board + 1));
        item.insert("capabilityState", tr("配置能力表（待硬件确认）"));
        item.insert("hardwareRates", baseRates);
        m_boardCapabilities.append(item);
    }

    // These values are explicitly simulation-only and never presented as a
    // board capability.  They exercise batching and display decimation.
    m_simulationStressRates = { 5000, 20000, 50000, 100000, 250000 };
}

QVariantList AcquisitionBackend::boardCapabilities() const { return m_boardCapabilities; }
QVariantList AcquisitionBackend::simulationStressRates() const { return m_simulationStressRates; }
// Display cadence is deliberately independent from the acquisition rate.
// Acquisition batches follow elapsed time, so this fixed 50 FPS repaint rate
// never determines simulated sample dt or signal phase.
int AcquisitionBackend::displayRefreshRate() const { return 50; }

QVariantList AcquisitionBackend::ratesForBoard(int boardIndex) const
{
    if (boardIndex < 0 || boardIndex >= m_boardCapabilities.size())
        return {};
    return m_boardCapabilities.at(boardIndex).toMap().value("hardwareRates").toList();
}

bool AcquisitionBackend::supportsHardwareRate(int boardIndex, int sampleRate) const
{
    return ratesForBoard(boardIndex).contains(sampleRate);
}

bool AcquisitionBackend::supportsSimulationStressRate(int sampleRate) const
{
    return m_simulationStressRates.contains(sampleRate);
}
