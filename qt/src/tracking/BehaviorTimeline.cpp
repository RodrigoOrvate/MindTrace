#include "BehaviorTimeline.h"
#include <QSGVertexColorMaterial>

BehaviorTimeline::BehaviorTimeline(QQuickItem *parent)
    : QQuickItem(parent), m_defaultColor(Qt::darkGray)
{
    setFlag(ItemHasContents, true);
}

BehaviorTimeline::~BehaviorTimeline() = default;

QColor BehaviorTimeline::defaultColor() const { return m_defaultColor; }
void BehaviorTimeline::setDefaultColor(const QColor &color) {
    if (m_defaultColor != color) {
        m_defaultColor = color;
        m_dataChanged = true;
        emit defaultColorChanged();
        update();
    }
}

void BehaviorTimeline::appendPoint(float timeSec, int labelId) {
    if (!m_points.empty() && (timeSec - m_points.back().timeSec) < 0.05f && m_points.back().labelId == labelId) {
        m_points.back().timeSec = timeSec; // extend the segment rather than adding a new point
    } else {
        m_points.push_back({timeSec, labelId});
    }
    m_dataChanged = true;
    update();
}

void BehaviorTimeline::clear() {
    m_points.clear();
    m_dataChanged = true;
    update();
}

void BehaviorTimeline::setLabelColor(int labelId, const QString& hexColor) {
    m_colors[labelId] = QColor(hexColor);
    m_dataChanged = true;
    update();
}

void BehaviorTimeline::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) {
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry != oldGeometry) {
        m_geometryChanged = true;
        update();
    }
}

QSGNode *BehaviorTimeline::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) {
    QSGGeometryNode *node = nullptr;
    QSGGeometry *geometry = nullptr;

    if (!oldNode) {
        node = new QSGGeometryNode;
        geometry = new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0);
        geometry->setDrawingMode(QSGGeometry::DrawTriangles);
        node->setGeometry(geometry);
        node->setFlag(QSGNode::OwnsGeometry);

        auto *material = new QSGVertexColorMaterial;
        node->setMaterial(material);
        node->setFlag(QSGNode::OwnsMaterial);
    } else {
        node = static_cast<QSGGeometryNode *>(oldNode);
        geometry = node->geometry();
    }

    if (m_points.empty() || width() <= 0 || height() <= 0) {
        geometry->allocate(0);
        return node;
    }

    if (m_geometryChanged || m_dataChanged) {
        m_geometryChanged = false;
        m_dataChanged = false;

        float maxTime = m_points.back().timeSec;
        if (maxTime <= 0.0f) maxTime = 1.0f;

        const int numSegments = static_cast<int>(m_points.size());
        geometry->allocate(numSegments * 6);
        QSGGeometry::ColoredPoint2D *vertices = geometry->vertexDataAsColoredPoint2D();

        const float rectW = width();
        const float rectH = height();

        for (size_t segmentIdx = 0; segmentIdx < m_points.size(); ++segmentIdx) {
            const float startTime = (segmentIdx == 0) ? 0.0f : m_points[segmentIdx - 1].timeSec;
            const float endTime   = m_points[segmentIdx].timeSec;

            const float startX = (startTime / maxTime) * rectW;
            const float endX   = (endTime   / maxTime) * rectW;

            const QColor segmentColor = m_colors.value(m_points[segmentIdx].labelId, m_defaultColor);

            // Pre-multiplied alpha required by QSGVertexColorMaterial.
            const uchar red   = static_cast<uchar>(segmentColor.red()   * segmentColor.alphaF());
            const uchar green = static_cast<uchar>(segmentColor.green() * segmentColor.alphaF());
            const uchar blue  = static_cast<uchar>(segmentColor.blue()  * segmentColor.alphaF());
            const uchar alpha = static_cast<uchar>(segmentColor.alpha());

            const int vertexOffset = static_cast<int>(segmentIdx) * 6;
            vertices[vertexOffset + 0].set(startX, 0,     red, green, blue, alpha);
            vertices[vertexOffset + 1].set(endX,   0,     red, green, blue, alpha);
            vertices[vertexOffset + 2].set(startX, rectH, red, green, blue, alpha);
            vertices[vertexOffset + 3].set(endX,   0,     red, green, blue, alpha);
            vertices[vertexOffset + 4].set(endX,   rectH, red, green, blue, alpha);
            vertices[vertexOffset + 5].set(startX, rectH, red, green, blue, alpha);
        }

        node->markDirty(QSGNode::DirtyGeometry);
    }

    return node;
}
