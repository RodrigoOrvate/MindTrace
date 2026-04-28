#include "video_input_enumerator.h"
#include "dshow_capture.h"

#include <QCameraDevice>
#include <QMediaDevices>
#include <QStringList>

VideoInputEnumerator::VideoInputEnumerator(QObject* parent)
    : QObject(parent)
{}

QVariantList VideoInputEnumerator::listVideoInputs() const
{
    QVariantList result;
    QStringList seenNames;

    for (const auto& qtDevice : QMediaDevices::videoInputs()) {
        QVariantMap deviceMap;
        deviceMap["name"]    = qtDevice.description();
        deviceMap["backend"] = "qt";
        result.append(deviceMap);
        seenNames.append(qtDevice.description());
    }

    for (const auto& dsInput : DShowCapture::enumerateInputs()) {
        QString deviceLabel = dsInput.name;
        if (deviceLabel.isEmpty())
            continue;

        if (seenNames.contains(deviceLabel, Qt::CaseInsensitive))
            deviceLabel += " [DirectShow]";
        else
            seenNames.append(deviceLabel);

        QVariantMap deviceMap;
        deviceMap["name"]         = deviceLabel;
        deviceMap["backend"]      = "dshow";
        deviceMap["hasComposite"] = dsInput.hasComposite;
        deviceMap["hasSVideo"]    = dsInput.hasSVideo;
        deviceMap["isHauppauge"]  = dsInput.isHauppauge;
        result.append(deviceMap);
    }

    return result;
}
