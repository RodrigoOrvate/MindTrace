#pragma once
#include <QQuickItem>
#include <QSGGeometryNode>
#include <QSGFlatColorMaterial>
#include <vector>
#include <QColor>

struct BehaviorPoint {
    float timeSec; // Time since start
    int   labelId; // 0, 1, 2...
};

class BehaviorTimeline : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QColor defaultColor READ defaultColor WRITE setDefaultColor NOTIFY defaultColorChanged)

public:
    explicit BehaviorTimeline(QQuickItem *parent = nullptr);
    ~BehaviorTimeline() override;

    // Must return true to participate in Scene Graph
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *updatePaintNodeData) override;

    Q_INVOKABLE void appendPoint(float timeSec, int labelId);
    Q_INVOKABLE void clear();
    
    // Register color mapping JSON from QML string/QVariantMap
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
