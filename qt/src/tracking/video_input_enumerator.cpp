#include "video_input_enumerator.h"

#include <QMediaDevices>
#include <QCameraDevice>
#include <QStringList>
#include "dshow_capture.h"

VideoInputEnumerator::VideoInputEnumerator(QObject* parent)
    : QObject(parent)
{}

QVariantList VideoInputEnumerator::listVideoInputs() const
{
    QVariantList result;
    QStringList seenNames;

    const auto qtDevices = QMediaDevices::videoInputs();
    for (const auto& dev : qtDevices) {
        QVariantMap map;
        map["name"] = dev.description();
        map["backend"] = "qt";
        result.append(map);
        seenNames.append(dev.description());
    }

    const auto dsInputs = DShowCapture::enumerateInputs();
    for (const auto& ds : dsInputs) {
        QString label = ds.name;
        if (label.isEmpty())
            continue;

        if (seenNames.contains(label, Qt::CaseInsensitive))
            label += " [DirectShow]";
        else
            seenNames.append(label);

        QVariantMap map;
        map["name"] = label;
        map["backend"] = "dshow";
        map["hasComposite"] = ds.hasComposite;
        map["hasSVideo"] = ds.hasSVideo;
        map["isHauppauge"] = ds.isHauppauge;
        result.append(map);
    }

    return result;
}
