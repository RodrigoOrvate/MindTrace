#pragma once

#include <QObject>
#include <QVariantList>

/// Enumerates available video input devices via Qt Multimedia.
class VideoInputEnumerator : public QObject
{
    Q_OBJECT
public:
    explicit VideoInputEnumerator(QObject* parent = nullptr);
    Q_INVOKABLE QVariantList listVideoInputs() const;
};

