#pragma once
#include <QColor>
#include <QQuickItem>
#include <QSGFlatColorMaterial>
#include <QSGGeometryNode>
#include <vector>

/// A single data point on the timeline: time offset and behaviour label.
struct BehaviorPoint {
    float timeSec = 0.0f; ///< seconds from session start
    int   labelId = 0;    ///< 0, 1, 2… — colour resolved via setLabelColor()
};

/// GPU-rendered etogram strip using Qt Scene Graph.
/// Append points at any time; the strip repaints on the next frame.
class BehaviorTimeline : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QColor defaultColor READ defaultColor WRITE setDefaultColor NOTIFY defaultColorChanged)

public:
    explicit BehaviorTimeline(QQuickItem *parent = nullptr);
    ~BehaviorTimeline() override;

    /// Required to participate in the Scene Graph rendering pipeline.
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *updatePaintNodeData) override;

    Q_INVOKABLE void appendPoint(float timeSec, int labelId);
    Q_INVOKABLE void clear();

    /// Register a hex colour string (e.g. "#ff0000") for the given label ID.
    Q_INVOKABLE void setLabelColor(int labelId, const QString& hexColor);

    QColor defaultColor() const;
    void setDefaultColor(const QColor &color);

signals:
    void defaultColorChanged();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    std::vector<BehaviorPoint> m_points;
    QMap<int, QColor> m_colors;
    QColor m_defaultColor;

    bool m_geometryChanged = false;
    bool m_dataChanged = false;
};
