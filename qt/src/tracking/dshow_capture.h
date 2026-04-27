#pragma once

#include <QString>
#include <QList>
#include <QImage>
#include <functional>

struct DShowVideoInput
{
    QString name;
    QString monikerDisplayName;
    bool isHauppauge = false;
    bool hasComposite = false;
    bool hasSVideo = false;
};

class DShowCapture
{
public:
    DShowCapture();
    ~DShowCapture();

    DShowCapture(const DShowCapture&) = delete;
    DShowCapture& operator=(const DShowCapture&) = delete;

    static QList<DShowVideoInput> enumerateInputs();

    bool start(const QString& cameraName,
               const QString& preferredInputType,
               const QString& preferredTvStandard,
               const std::function<void(const QImage&)>& onFrame,
               QString* errorOut);
    void stop();
    bool isRunning() const;

private:
    struct Impl;
    Impl* m_impl = nullptr;
};
