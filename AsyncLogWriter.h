#pragma once

#include <QString>

// Shared, process-local asynchronous log sink.  Global application logs are
// retained and rotated; recording logs use the same background writer but are
// kept inside their recording session and are never included in global cleanup.
namespace AsyncLogWriter {
void appendGlobal(const QString &filePath, const QString &line);
void appendRecording(const QString &filePath, const QString &line);
void cleanupGlobalDirectory(const QString &directory);
void flushRecording(const QString &filePath);
void shutdown();
}
