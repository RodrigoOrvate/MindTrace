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
    // Basic compression: don't add point if time differs by < 0.1 sec (too dense)
    if (!m_points.empty() && (timeSec - m_points.back().timeSec) < 0.05f && m_points.back().labelId == labelId) {
        m_points.back().timeSec = timeSec; // just stretch the duration
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
        if (maxTime <= 0.0f) maxTime = 1.0f; // Prevent div zero

        // We draw quads (2 triangles, 6 vertices) for each segment.
        // A segment goes from point[i] to point[i+1].
        int numSegments = m_points.size(); 
        geometry->allocate(numSegments * 6);
        QSGGeometry::ColoredPoint2D *vertices = geometry->vertexDataAsColoredPoint2D();

        float rectW = width();
        float rectH = height();

        for (size_t i = 0; i < m_points.size(); ++i) {
            float t1 = (i == 0) ? 0.0f : m_points[i-1].timeSec;
            float t2 = m_points[i].timeSec;

            float x1 = (t1 / maxTime) * rectW;
            float x2 = (t2 / maxTime) * rectW;
            
            int label = m_points[i].labelId;
            QColor qcol = m_colors.value(label, m_defaultColor);
            
            // Premultiply alphas for QSG
            uchar r = qcol.red() * qcol.alphaF();
            uchar g = qcol.green() * qcol.alphaF();
            uchar b = qcol.blue() * qcol.alphaF();
            uchar a = qcol.alpha();

            int vIdx = i * 6;
            // Triangle 1
            vertices[vIdx+0].set(x1, 0, r, g, b, a);
            vertices[vIdx+1].set(x2, 0, r, g, b, a);
            vertices[vIdx+2].set(x1, rectH, r, g, b, a);
            // Triangle 2
            vertices[vIdx+3].set(x2, 0, r, g, b, a);
            vertices[vIdx+4].set(x2, rectH, r, g, b, a);
            vertices[vIdx+5].set(x1, rectH, r, g, b, a);
        }

        node->markDirty(QSGNode::DirtyGeometry);
    }

    return node;
}
