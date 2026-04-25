#include "dshow_capture.h"

#ifdef Q_OS_WIN

#include <windows.h>
#include <dshow.h>
#include <dvdmedia.h>
#include <oaidl.h>
#include <atomic>
#include <vector>
#include <cstring>
#include <QDebug>
#include <QByteArray>

// qedit.h is deprecated and often missing in modern SDKs.
// Minimal declarations for Sample Grabber interfaces/GUIDs.
struct __declspec(uuid("0579154A-2B53-4994-B0D0-E773148EFF85")) ISampleGrabberCB : public IUnknown
{
    virtual HRESULT STDMETHODCALLTYPE SampleCB(double sampleTime, IMediaSample* sample) = 0;
    virtual HRESULT STDMETHODCALLTYPE BufferCB(double sampleTime, BYTE* buffer, long bufferLen) = 0;
};

struct __declspec(uuid("6B652FFF-11FE-4fce-92AD-0266B5D7C78F")) ISampleGrabber : public IUnknown
{
    virtual HRESULT STDMETHODCALLTYPE SetOneShot(BOOL oneShot) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetMediaType(const AM_MEDIA_TYPE* mediaType) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetConnectedMediaType(AM_MEDIA_TYPE* mediaType) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetBufferSamples(BOOL bufferThem) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetCurrentBuffer(long* bufferSize, long* buffer) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetCurrentSample(IMediaSample** sample) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetCallback(ISampleGrabberCB* callback, long whichMethodToCallback) = 0;
};

static const CLSID CLSID_SampleGrabber =
{0xc1f400a0, 0x3f08, 0x11d3, {0x9f, 0x0b, 0x00, 0x60, 0x08, 0x03, 0x9e, 0x37}};

// Some Windows SDK variants do not expose CLSID_NullRenderer in headers.
static const CLSID CLSID_NullRenderer_DShow =
{0xc1f400a4, 0x3f08, 0x11d3, {0x9f, 0x0b, 0x00, 0x60, 0x08, 0x03, 0x9e, 0x37}};

template <typename T>
static void safeRelease(T*& p)
{
    if (p) {
        p->Release();
        p = nullptr;
    }
}

static QString guidToFourCC(const GUID& g)
{
    char cc[5] = {
        static_cast<char>( g.Data1        & 0xFF),
        static_cast<char>((g.Data1 >>  8) & 0xFF),
        static_cast<char>((g.Data1 >> 16) & 0xFF),
        static_cast<char>((g.Data1 >> 24) & 0xFF),
        '\0'
    };
    bool printable = true;
    for (int i = 0; i < 4; ++i)
        if (static_cast<unsigned char>(cc[i]) < 0x20) { printable = false; break; }
    if (printable) return QString::fromLatin1(cc);
    return QString("{%1}").arg(g.Data1, 8, 16, QChar('0'));
}

static QString bstrToQString(BSTR b)
{
    if (!b) return QString();
    return QString::fromWCharArray(b);
}

static QString friendlyNameFromMoniker(IMoniker* moniker)
{
    if (!moniker) return QString();

    IPropertyBag* bag = nullptr;
    if (FAILED(moniker->BindToStorage(nullptr, nullptr, IID_IPropertyBag, reinterpret_cast<void**>(&bag))))
        return QString();

    VARIANT varName;
    VariantInit(&varName);
    QString result;
    if (SUCCEEDED(bag->Read(L"FriendlyName", &varName, nullptr)) && varName.vt == VT_BSTR) {
        result = bstrToQString(varName.bstrVal);
    }
    VariantClear(&varName);
    bag->Release();
    return result;
}

static QString displayNameFromMoniker(IMoniker* moniker)
{
    if (!moniker) return QString();
    IBindCtx* bindCtx = nullptr;
    LPOLESTR display = nullptr;
    QString out;
    if (SUCCEEDED(CreateBindCtx(0, &bindCtx))) {
        if (SUCCEEDED(moniker->GetDisplayName(bindCtx, nullptr, &display)) && display) {
            out = QString::fromWCharArray(display);
            CoTaskMemFree(display);
        }
        bindCtx->Release();
    }
    return out;
}

static int findCrossbarOutputForVideo(IAMCrossbar* crossbar)
{
    if (!crossbar) return -1;
    long outPins = 0, inPins = 0;
    if (FAILED(crossbar->get_PinCounts(&outPins, &inPins)))
        return -1;

    for (long o = 0; o < outPins; ++o) {
        long related = 0;
        long type = 0;
        if (SUCCEEDED(crossbar->get_CrossbarPinInfo(FALSE, o, &related, &type))) {
            if (type == PhysConn_Video_VideoDecoder)
                return static_cast<int>(o);
        }
    }
    return -1;
}

static int findCrossbarInputForComposite(IAMCrossbar* crossbar)
{
    if (!crossbar) return -1;
    long outPins = 0, inPins = 0;
    if (FAILED(crossbar->get_PinCounts(&outPins, &inPins)))
        return -1;

    for (long i = 0; i < inPins; ++i) {
        long related = 0;
        long type = 0;
        if (SUCCEEDED(crossbar->get_CrossbarPinInfo(TRUE, i, &related, &type))) {
            if (type == PhysConn_Video_Composite)
                return static_cast<int>(i);
        }
    }
    return -1;
}

static int findCrossbarInputForSVideo(IAMCrossbar* crossbar)
{
    if (!crossbar) return -1;
    long outPins = 0, inPins = 0;
    if (FAILED(crossbar->get_PinCounts(&outPins, &inPins)))
        return -1;

    for (long i = 0; i < inPins; ++i) {
        long related = 0;
        long type = 0;
        if (SUCCEEDED(crossbar->get_CrossbarPinInfo(TRUE, i, &related, &type))) {
            if (type == PhysConn_Video_SVideo)
                return static_cast<int>(i);
        }
    }
    return -1;
}

static bool hasCompositeInputOnFilter(IBaseFilter* capFilter)
{
    if (!capFilter) return false;

    IAMCrossbar* crossbar = nullptr;
    if (FAILED(capFilter->QueryInterface(IID_IAMCrossbar, reinterpret_cast<void**>(&crossbar))))
        return false;

    const bool ok = findCrossbarInputForComposite(crossbar) >= 0;
    crossbar->Release();
    return ok;
}

static bool hasSVideoInputOnFilter(IBaseFilter* capFilter)
{
    if (!capFilter) return false;

    IAMCrossbar* crossbar = nullptr;
    if (FAILED(capFilter->QueryInterface(IID_IAMCrossbar, reinterpret_cast<void**>(&crossbar))))
        return false;

    const bool ok = findCrossbarInputForSVideo(crossbar) >= 0;
    crossbar->Release();
    return ok;
}

static IAMCrossbar* tryFindCrossbar(ICaptureGraphBuilder2* builder, IBaseFilter* capFilter)
{
    if (!builder || !capFilter) return nullptr;

    IAMCrossbar* crossbar = nullptr;
    if (SUCCEEDED(builder->FindInterface(&LOOK_UPSTREAM_ONLY, nullptr, capFilter,
                                         IID_IAMCrossbar, reinterpret_cast<void**>(&crossbar))))
        return crossbar;
    if (SUCCEEDED(builder->FindInterface(&PIN_CATEGORY_CAPTURE, &MEDIATYPE_Interleaved, capFilter,
                                         IID_IAMCrossbar, reinterpret_cast<void**>(&crossbar))))
        return crossbar;
    if (SUCCEEDED(builder->FindInterface(&PIN_CATEGORY_CAPTURE, &MEDIATYPE_Video, capFilter,
                                         IID_IAMCrossbar, reinterpret_cast<void**>(&crossbar))))
        return crossbar;
    if (SUCCEEDED(builder->FindInterface(&PIN_CATEGORY_PREVIEW, &MEDIATYPE_Interleaved, capFilter,
                                         IID_IAMCrossbar, reinterpret_cast<void**>(&crossbar))))
        return crossbar;
    if (SUCCEEDED(builder->FindInterface(&PIN_CATEGORY_PREVIEW, &MEDIATYPE_Video, capFilter,
                                         IID_IAMCrossbar, reinterpret_cast<void**>(&crossbar))))
        return crossbar;
    return nullptr;
}

static void tryConfigureAnalogTvStandard(ICaptureGraphBuilder2* builder, IBaseFilter* capFilter)
{
    if (!capFilter) return;

    IAMAnalogVideoDecoder* decoder = nullptr;
    if (builder) {
        if (FAILED(builder->FindInterface(&LOOK_UPSTREAM_ONLY, nullptr, capFilter,
                                          IID_IAMAnalogVideoDecoder, reinterpret_cast<void**>(&decoder)))) {
            // Fallback: some drivers expose it directly on the capture filter.
            capFilter->QueryInterface(IID_IAMAnalogVideoDecoder, reinterpret_cast<void**>(&decoder));
        }
    } else {
        capFilter->QueryInterface(IID_IAMAnalogVideoDecoder, reinterpret_cast<void**>(&decoder));
    }
    if (!decoder) return;

    long available = 0;
    if (SUCCEEDED(decoder->get_AvailableTVFormats(&available)) && available != 0) {
        const long preferred[] = {
            AnalogVideo_PAL_M,
            AnalogVideo_NTSC_M,
            AnalogVideo_PAL_N,
            AnalogVideo_PAL_B,
            AnalogVideo_PAL_G
        };
        for (long stdFmt : preferred) {
            if (available & stdFmt) {
                decoder->put_TVFormat(stdFmt);
                break;
            }
        }
    }
    decoder->Release();
}

class GrabberCallback final : public ISampleGrabberCB
{
public:
    explicit GrabberCallback(std::function<void(const QImage&)> onFrame)
        : m_onFrame(std::move(onFrame))
    {}

    void setVideoFormat(int w, int h, bool bottomUp, const GUID& subtype, int bitCount)
    {
        m_width = w;
        m_height = h;
        m_bottomUp = bottomUp;
        m_subtype = subtype;
        m_bitCount = bitCount;
    }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == __uuidof(ISampleGrabberCB)) {
            *ppv = static_cast<ISampleGrabberCB*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override
    {
        return ++m_refCount;
    }

    STDMETHODIMP_(ULONG) Release() override
    {
        const ULONG v = --m_refCount;
        if (v == 0) delete this;
        return v;
    }

    STDMETHODIMP SampleCB(double, IMediaSample*) override
    {
        return E_NOTIMPL;
    }

    STDMETHODIMP BufferCB(double, BYTE* buffer, long bufferLen) override
    {
        if (!buffer || bufferLen <= 0 || m_width <= 0 || m_height <= 0 || !m_onFrame)
            return S_OK;

        const QString subtypeStr = guidToFourCC(m_subtype);

        if (!m_firstFrameLogged.exchange(true))
            qDebug() << "[DShow] Primeiro frame recebido: subtype=" << subtypeStr
                     << "bufferLen=" << bufferLen << "w=" << m_width << "h=" << m_height;

        if (IsEqualGUID(m_subtype, MEDIASUBTYPE_YUY2)) {
            const int srcStride = ((m_width * 2 + 3) / 4) * 4;
            if (bufferLen < srcStride * m_height)
                return S_OK;

            QImage img(m_width, m_height, QImage::Format_RGB888);
            if (img.isNull())
                return S_OK;

            auto clamp8 = [](int v) -> int { return v < 0 ? 0 : (v > 255 ? 255 : v); };
            for (int y = 0; y < m_height; ++y) {
                // Force top-down for NV12 preview/capture path.
                // Some drivers report biHeight inconsistently for NV12.
                const int srcY = y;
                const BYTE* srcRow = buffer + srcY * srcStride;
                uchar* dst = img.scanLine(y);
                for (int x = 0; x < m_width; x += 2) {
                    const int i = x * 2;
                    const int y0 = srcRow[i + 0];
                    const int u  = srcRow[i + 1] - 128;
                    const int y1 = srcRow[i + 2];
                    const int v  = srcRow[i + 3] - 128;

                    const int c0 = y0 - 16;
                    const int c1 = y1 - 16;
                    const int r0 = clamp8((298 * c0 + 409 * v + 128) >> 8);
                    const int g0 = clamp8((298 * c0 - 100 * u - 208 * v + 128) >> 8);
                    const int b0 = clamp8((298 * c0 + 516 * u + 128) >> 8);
                    const int r1 = clamp8((298 * c1 + 409 * v + 128) >> 8);
                    const int g1 = clamp8((298 * c1 - 100 * u - 208 * v + 128) >> 8);
                    const int b1 = clamp8((298 * c1 + 516 * u + 128) >> 8);

                    const int d = x * 3;
                    dst[d + 0] = static_cast<uchar>(r0);
                    dst[d + 1] = static_cast<uchar>(g0);
                    dst[d + 2] = static_cast<uchar>(b0);
                    if (x + 1 < m_width) {
                        dst[d + 3] = static_cast<uchar>(r1);
                        dst[d + 4] = static_cast<uchar>(g1);
                        dst[d + 5] = static_cast<uchar>(b1);
                    }
                }
            }
            m_onFrame(img);
            return S_OK;
        }

        if (IsEqualGUID(m_subtype, MEDIASUBTYPE_UYVY)) {
            // UYVY macropixel layout: U0 Y0 V0 Y1 (byte order differs from YUY2)
            const int srcStride = ((m_width * 2 + 3) / 4) * 4;
            if (bufferLen < srcStride * m_height)
                return S_OK;

            QImage img(m_width, m_height, QImage::Format_RGB888);
            if (img.isNull())
                return S_OK;

            auto clamp8 = [](int v) -> int { return v < 0 ? 0 : (v > 255 ? 255 : v); };
            for (int y = 0; y < m_height; ++y) {
                const int srcY = m_bottomUp ? (m_height - 1 - y) : y;
                const BYTE* srcRow = buffer + srcY * srcStride;
                uchar* dst = img.scanLine(y);
                for (int x = 0; x < m_width; x += 2) {
                    const int i = x * 2;
                    const int u  = srcRow[i + 0] - 128;
                    const int y0 = srcRow[i + 1];
                    const int v  = srcRow[i + 2] - 128;
                    const int y1 = srcRow[i + 3];

                    const int c0 = y0 - 16;
                    const int c1 = y1 - 16;
                    const int r0 = clamp8((298 * c0 + 409 * v + 128) >> 8);
                    const int g0 = clamp8((298 * c0 - 100 * u - 208 * v + 128) >> 8);
                    const int b0 = clamp8((298 * c0 + 516 * u + 128) >> 8);
                    const int r1 = clamp8((298 * c1 + 409 * v + 128) >> 8);
                    const int g1 = clamp8((298 * c1 - 100 * u - 208 * v + 128) >> 8);
                    const int b1 = clamp8((298 * c1 + 516 * u + 128) >> 8);

                    const int d = x * 3;
                    dst[d + 0] = static_cast<uchar>(r0);
                    dst[d + 1] = static_cast<uchar>(g0);
                    dst[d + 2] = static_cast<uchar>(b0);
                    if (x + 1 < m_width) {
                        dst[d + 3] = static_cast<uchar>(r1);
                        dst[d + 4] = static_cast<uchar>(g1);
                        dst[d + 5] = static_cast<uchar>(b1);
                    }
                }
            }
            m_onFrame(img);
            return S_OK;
        }

        if (subtypeStr == "NV12") {
            int yStride = m_width;
            if (m_height > 0) {
                const int derived = (bufferLen * 2) / (m_height * 3);
                if (derived >= m_width)
                    yStride = (derived / 2) * 2;
            }
            int uvStride = yStride;
            int needBytes = yStride * m_height + uvStride * (m_height / 2);
            if (needBytes > bufferLen) {
                yStride = m_width;
                uvStride = m_width;
                needBytes = yStride * m_height + uvStride * (m_height / 2);
            }
            if (needBytes > bufferLen)
                return S_OK;

            QImage img(m_width, m_height, QImage::Format_RGB888);
            if (img.isNull())
                return S_OK;

            auto clamp8 = [](int v) -> int { return v < 0 ? 0 : (v > 255 ? 255 : v); };
            const BYTE* yPlane = buffer;
            const BYTE* uvPlane = buffer + yStride * m_height;
            for (int y = 0; y < m_height; ++y) {
                const int srcY = m_bottomUp ? (m_height - 1 - y) : y;
                const BYTE* yRow = yPlane + srcY * yStride;
                const BYTE* uvRow = uvPlane + (srcY / 2) * uvStride;
                uchar* dst = img.scanLine(y);
                for (int x = 0; x < m_width; ++x) {
                    const int Y = yRow[x];
                    const int uvIdx = x & ~1;
                    const int U = uvRow[uvIdx + 0] - 128;
                    const int V = uvRow[uvIdx + 1] - 128;
                    const int c = Y - 16;
                    const int r = clamp8((298 * c + 409 * V + 128) >> 8);
                    const int g = clamp8((298 * c - 100 * U - 208 * V + 128) >> 8);
                    const int b = clamp8((298 * c + 516 * U + 128) >> 8);
                    const int d = x * 3;
                    dst[d + 0] = static_cast<uchar>(r);
                    dst[d + 1] = static_cast<uchar>(g);
                    dst[d + 2] = static_cast<uchar>(b);
                }
            }
            m_onFrame(img);
            return S_OK;
        }

        if (subtypeStr == "MJPG" || subtypeStr == "JPEG") {
            const QByteArray jpg(reinterpret_cast<const char*>(buffer), bufferLen);
            QImage img = QImage::fromData(jpg, "JPG");
            if (img.isNull())
                img = QImage::fromData(jpg);
            if (img.isNull())
                return S_OK;
            if (img.format() != QImage::Format_RGB888)
                img = img.convertToFormat(QImage::Format_RGB888);
            m_onFrame(img);
            return S_OK;
        }

        const bool isRgb32 = IsEqualGUID(m_subtype, MEDIASUBTYPE_RGB32) || m_bitCount == 32;
        const bool isRgb24 = IsEqualGUID(m_subtype, MEDIASUBTYPE_RGB24) || m_bitCount == 24;
        if (!isRgb32 && !isRgb24) {
            if (!m_unsupportedSubtypeLogged.exchange(true)) {
                qDebug() << "[DShow] Subtype nao suportado no callback:" << subtypeStr
                         << "bitCount=" << m_bitCount
                         << "len=" << bufferLen
                         << "res=" << m_width << "x" << m_height;
            }
            return S_OK;
        }
        const int bytesPerPixel = isRgb32 ? 4 : 3;
        const int srcStride = ((m_width * bytesPerPixel + 3) / 4) * 4;
        if (bufferLen < srcStride * m_height)
            return S_OK;

        QImage img(m_width, m_height, isRgb32 ? QImage::Format_ARGB32 : QImage::Format_BGR888);
        if (img.isNull())
            return S_OK;

        for (int y = 0; y < m_height; ++y) {
            const int srcY = m_bottomUp ? (m_height - 1 - y) : y;
            const BYTE* srcRow = buffer + srcY * srcStride;
            std::memcpy(img.scanLine(y), srcRow, static_cast<size_t>(m_width * bytesPerPixel));
        }

        m_onFrame(isRgb32 ? img.convertToFormat(QImage::Format_RGB888) : img);
        return S_OK;
    }

private:
    std::atomic<ULONG> m_refCount {1};
    std::atomic<bool>  m_firstFrameLogged {false};
    std::atomic<bool>  m_unsupportedSubtypeLogged {false};
    std::function<void(const QImage&)> m_onFrame;
    int m_width = 0;
    int m_height = 0;
    bool m_bottomUp = false;
    GUID m_subtype = MEDIASUBTYPE_RGB24;
    int m_bitCount = 24;
};

struct DShowCapture::Impl
{
    IGraphBuilder* graph = nullptr;
    ICaptureGraphBuilder2* captureBuilder = nullptr;
    IMediaControl* mediaControl = nullptr;
    IBaseFilter* captureFilter = nullptr;
    IBaseFilter* sampleGrabberFilter = nullptr;
    ISampleGrabber* sampleGrabber = nullptr;
    IBaseFilter* nullRenderer = nullptr;
    GrabberCallback* callback = nullptr;
    bool running = false;
    bool comInitialized = false;
};

DShowCapture::DShowCapture()
    : m_impl(new Impl())
{}

DShowCapture::~DShowCapture()
{
    stop();
    delete m_impl;
    m_impl = nullptr;
}

QList<DShowVideoInput> DShowCapture::enumerateInputs()
{
    QList<DShowVideoInput> out;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool needUninit = SUCCEEDED(hr);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        return out;
    }

    ICreateDevEnum* devEnum = nullptr;
    IEnumMoniker* enumMoniker = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_SystemDeviceEnum, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ICreateDevEnum, reinterpret_cast<void**>(&devEnum))) &&
        SUCCEEDED(devEnum->CreateClassEnumerator(CLSID_VideoInputDeviceCategory, &enumMoniker, 0)) &&
        enumMoniker) {
        IMoniker* moniker = nullptr;
        while (enumMoniker->Next(1, &moniker, nullptr) == S_OK) {
            DShowVideoInput item;
            item.name = friendlyNameFromMoniker(moniker);
            item.monikerDisplayName = displayNameFromMoniker(moniker);
            const QString lowName = item.name.toLower();
            item.isHauppauge = lowName.contains("hauppauge") || lowName.contains("hvr");

            IBaseFilter* filter = nullptr;
            if (SUCCEEDED(moniker->BindToObject(nullptr, nullptr, IID_IBaseFilter,
                                                reinterpret_cast<void**>(&filter)))) {
                item.hasComposite = hasCompositeInputOnFilter(filter);
                item.hasSVideo = hasSVideoInputOnFilter(filter);
                filter->Release();
            }

            // USB Hauppauge cards (HVR series): the crossbar filter is a separate upstream
            // virtual filter — hasCompositeInputOnFilter (QueryInterface on capture filter)
            // returns false even though the composite input exists. Force-flag it by name.
            if (item.isHauppauge && !item.hasComposite)
                item.hasComposite = true;

            out.append(item);
            moniker->Release();
        }
    }

    safeRelease(enumMoniker);
    safeRelease(devEnum);

    if (needUninit)
        CoUninitialize();
    return out;
}

bool DShowCapture::start(const QString& cameraName,
                         const QString& preferredInputType,
                         const std::function<void(const QImage&)>& onFrame,
                         QString* errorOut)
{
    stop();

    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool needUninit = SUCCEEDED(hr);
    m_impl->comInitialized = needUninit;
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        if (errorOut) *errorOut = "DirectShow: falha ao inicializar COM.";
        return false;
    }

    ICreateDevEnum* devEnum = nullptr;
    IEnumMoniker* enumMoniker = nullptr;
    IMoniker* selectedMoniker = nullptr;

    do {
        hr = CoCreateInstance(CLSID_SystemDeviceEnum, nullptr, CLSCTX_INPROC_SERVER,
                              IID_ICreateDevEnum, reinterpret_cast<void**>(&devEnum));
        if (FAILED(hr)) break;

        hr = devEnum->CreateClassEnumerator(CLSID_VideoInputDeviceCategory, &enumMoniker, 0);
        if (FAILED(hr) || !enumMoniker) break;

        IMoniker* moniker = nullptr;
        while (enumMoniker->Next(1, &moniker, nullptr) == S_OK) {
            const QString name = friendlyNameFromMoniker(moniker);
            if (name == cameraName) {
                selectedMoniker = moniker;
                break;
            }
            moniker->Release();
        }
        if (!selectedMoniker) {
            enumMoniker->Reset();
            if (enumMoniker->Next(1, &selectedMoniker, nullptr) != S_OK)
                break;
        }

        hr = CoCreateInstance(CLSID_FilterGraph, nullptr, CLSCTX_INPROC_SERVER,
                              IID_IGraphBuilder, reinterpret_cast<void**>(&m_impl->graph));
        if (FAILED(hr)) break;

        hr = CoCreateInstance(CLSID_CaptureGraphBuilder2, nullptr, CLSCTX_INPROC_SERVER,
                              IID_ICaptureGraphBuilder2, reinterpret_cast<void**>(&m_impl->captureBuilder));
        if (FAILED(hr)) break;

        hr = m_impl->captureBuilder->SetFiltergraph(m_impl->graph);
        if (FAILED(hr)) break;

        hr = selectedMoniker->BindToObject(nullptr, nullptr, IID_IBaseFilter,
                                           reinterpret_cast<void**>(&m_impl->captureFilter));
        if (FAILED(hr) || !m_impl->captureFilter) {
            qDebug() << "[DShow] BindToObject falhou para:" << cameraName << "hr=" << Qt::hex << (uint)hr;
            break;
        }

        qDebug() << "[DShow] Capture filter vinculado:" << cameraName;

        hr = m_impl->graph->AddFilter(m_impl->captureFilter, L"Capture");
        if (FAILED(hr)) break;

        hr = CoCreateInstance(CLSID_SampleGrabber, nullptr, CLSCTX_INPROC_SERVER,
                              IID_IBaseFilter, reinterpret_cast<void**>(&m_impl->sampleGrabberFilter));
        if (FAILED(hr)) break;

        hr = m_impl->sampleGrabberFilter->QueryInterface(__uuidof(ISampleGrabber),
                                                         reinterpret_cast<void**>(&m_impl->sampleGrabber));
        if (FAILED(hr) || !m_impl->sampleGrabber) break;

        AM_MEDIA_TYPE mt;
        std::memset(&mt, 0, sizeof(mt));
        mt.majortype = MEDIATYPE_Video;
        // No formattype constraint: allows both FORMAT_VideoInfo and FORMAT_VideoInfo2
        // (Hauppauge HVR and similar TV tuner cards often negotiate FORMAT_VideoInfo2)
        hr = m_impl->sampleGrabber->SetMediaType(&mt);
        if (FAILED(hr)) break;

        hr = m_impl->graph->AddFilter(m_impl->sampleGrabberFilter, L"SampleGrabber");
        if (FAILED(hr)) break;

        hr = CoCreateInstance(CLSID_NullRenderer_DShow, nullptr, CLSCTX_INPROC_SERVER,
                              IID_IBaseFilter, reinterpret_cast<void**>(&m_impl->nullRenderer));
        if (FAILED(hr)) break;

        hr = m_impl->graph->AddFilter(m_impl->nullRenderer, L"NullRenderer");
        if (FAILED(hr)) break;

        const QString camLower = cameraName.trimmed().toLower();
        const bool preferPreviewFirst = camLower.contains("virtual camera")
                                        || camLower.contains("obs virtual");
        if (preferPreviewFirst) {
            qDebug() << "[DShow] Virtual camera detectada, tentando PREVIEW primeiro...";
            hr = m_impl->captureBuilder->RenderStream(&PIN_CATEGORY_PREVIEW, &MEDIATYPE_Video,
                                                      m_impl->captureFilter,
                                                      m_impl->sampleGrabberFilter,
                                                      m_impl->nullRenderer);
            if (FAILED(hr)) {
                qDebug() << "[DShow] RenderStream PREVIEW falhou (hr=" << Qt::hex << (uint)hr << "), tentando CAPTURE...";
                hr = m_impl->captureBuilder->RenderStream(&PIN_CATEGORY_CAPTURE, &MEDIATYPE_Video,
                                                          m_impl->captureFilter,
                                                          m_impl->sampleGrabberFilter,
                                                          m_impl->nullRenderer);
            }
        } else {
            hr = m_impl->captureBuilder->RenderStream(&PIN_CATEGORY_CAPTURE, &MEDIATYPE_Video,
                                                      m_impl->captureFilter,
                                                      m_impl->sampleGrabberFilter,
                                                      m_impl->nullRenderer);
            if (FAILED(hr)) {
                qDebug() << "[DShow] RenderStream CAPTURE falhou (hr=" << Qt::hex << (uint)hr << "), tentando PREVIEW...";
                hr = m_impl->captureBuilder->RenderStream(&PIN_CATEGORY_PREVIEW, &MEDIATYPE_Video,
                                                          m_impl->captureFilter,
                                                          m_impl->sampleGrabberFilter,
                                                          m_impl->nullRenderer);
            }
        }
        if (FAILED(hr)) {
            qDebug() << "[DShow] RenderStream falhou completamente hr=" << Qt::hex << (uint)hr;
            break;
        }
        qDebug() << "[DShow] RenderStream OK";

        // Route crossbar AFTER RenderStream — for TV tuner cards (e.g. Hauppauge HVR-1955),
        // RenderStream is what adds the upstream crossbar filter to the graph. Attempting
        // FindInterface before this call returns nothing and leaves the card on its default
        // input (tuner/no signal), producing a black frame.
        tryConfigureAnalogTvStandard(m_impl->captureBuilder, m_impl->captureFilter);

        {
            IAMCrossbar* crossbar = tryFindCrossbar(m_impl->captureBuilder, m_impl->captureFilter);
            if (!crossbar) {
                qDebug() << "[DShow] tryFindCrossbar nulo, tentando QueryInterface direto no captureFilter...";
                m_impl->captureFilter->QueryInterface(IID_IAMCrossbar,
                                                      reinterpret_cast<void**>(&crossbar));
            }
            if (crossbar) {
                const int outPin = findCrossbarOutputForVideo(crossbar);
                int inPin = -1;
                const QString pref = preferredInputType.trimmed().toLower();
                if (pref.contains("s-video") || pref.contains("svideo"))
                    inPin = findCrossbarInputForSVideo(crossbar);
                else if (pref.contains("composite"))
                    inPin = findCrossbarInputForComposite(crossbar);
                else
                    inPin = findCrossbarInputForComposite(crossbar);
                if (inPin < 0)
                    inPin = findCrossbarInputForSVideo(crossbar);
                qDebug() << "[DShow] Crossbar encontrado — outPin=" << outPin << "inPin=" << inPin
                         << "preferido=" << preferredInputType;
                if (outPin >= 0 && inPin >= 0) {
                    HRESULT hrRoute = crossbar->Route(outPin, inPin);
                    qDebug() << "[DShow] Crossbar Route hr=" << Qt::hex << (uint)hrRoute;
                } else {
                    qDebug() << "[DShow] Crossbar: pinos invalidos, roteamento nao aplicado";
                }
                crossbar->Release();
            } else {
                qDebug() << "[DShow] Crossbar NAO encontrado — card pode nao ter IAMCrossbar";
            }
        }

        hr = m_impl->sampleGrabber->SetBufferSamples(FALSE);
        if (FAILED(hr)) break;
        hr = m_impl->sampleGrabber->SetOneShot(FALSE);
        if (FAILED(hr)) break;

        AM_MEDIA_TYPE connectedType;
        std::memset(&connectedType, 0, sizeof(connectedType));
        hr = m_impl->sampleGrabber->GetConnectedMediaType(&connectedType);
        if (FAILED(hr)) break;

        int width = 0;
        int height = 0;
        bool bottomUp = false;
        int bitCount = 24;
        GUID subtype = connectedType.subtype;
        if (connectedType.formattype == FORMAT_VideoInfo && connectedType.pbFormat &&
            connectedType.cbFormat >= sizeof(VIDEOINFOHEADER)) {
            const auto* vih = reinterpret_cast<const VIDEOINFOHEADER*>(connectedType.pbFormat);
            width = vih->bmiHeader.biWidth;
            const LONG h = vih->bmiHeader.biHeight;
            bottomUp = (h > 0);
            height = (h > 0 ? static_cast<int>(h) : static_cast<int>(-h));
            bitCount = static_cast<int>(vih->bmiHeader.biBitCount);
        } else if (connectedType.formattype == FORMAT_VideoInfo2 && connectedType.pbFormat &&
                   connectedType.cbFormat >= sizeof(VIDEOINFOHEADER2)) {
            const auto* vih2 = reinterpret_cast<const VIDEOINFOHEADER2*>(connectedType.pbFormat);
            width = vih2->bmiHeader.biWidth;
            const LONG h = vih2->bmiHeader.biHeight;
            bottomUp = (h > 0);
            height = (h > 0 ? static_cast<int>(h) : static_cast<int>(-h));
            bitCount = static_cast<int>(vih2->bmiHeader.biBitCount);
        }
        if (connectedType.cbFormat && connectedType.pbFormat)
            CoTaskMemFree(connectedType.pbFormat);
        if (connectedType.pUnk)
            connectedType.pUnk->Release();

        qDebug() << "[DShow] ConnectedMediaType: subtype=" << guidToFourCC(subtype)
                 << "width=" << width << "height=" << height
                 << "bitCount=" << bitCount << "bottomUp=" << bottomUp;

        if (width <= 0 || height <= 0) {
            qDebug() << "[DShow] Dimensoes invalidas — RenderStream negociou formato desconhecido";
            if (errorOut) *errorOut = "DirectShow: formato de video invalido.";
            break;
        }

        const QString camLowerForFlip = cameraName.trimmed().toLower();
        const bool forceVerticalFlip = camLowerForFlip.contains("obs virtual")
                                       || camLowerForFlip.contains("virtual camera");
        auto wrappedOnFrame = [onFrame, forceVerticalFlip](const QImage& frame) {
            if (!onFrame)
                return;
            if (!forceVerticalFlip) {
                onFrame(frame);
                return;
            }
            onFrame(frame.mirrored(false, true));
        };

        m_impl->callback = new GrabberCallback(wrappedOnFrame);
        m_impl->callback->setVideoFormat(width, height, bottomUp, subtype, bitCount);
        hr = m_impl->sampleGrabber->SetCallback(m_impl->callback, 1 /* BufferCB */);
        if (FAILED(hr)) break;

        hr = m_impl->graph->QueryInterface(IID_IMediaControl, reinterpret_cast<void**>(&m_impl->mediaControl));
        if (FAILED(hr) || !m_impl->mediaControl) break;

        hr = m_impl->mediaControl->Run();
        if (FAILED(hr)) break;

        m_impl->running = true;

        if (selectedMoniker) selectedMoniker->Release();
        safeRelease(enumMoniker);
        safeRelease(devEnum);
        return true;
    } while (false);

    if (selectedMoniker) selectedMoniker->Release();
    safeRelease(enumMoniker);
    safeRelease(devEnum);
    stop();
    if (errorOut && errorOut->isEmpty())
        *errorOut = "DirectShow: falha ao iniciar captura.";
    return false;
}

void DShowCapture::stop()
{
    if (!m_impl) return;

    if (m_impl->mediaControl)
        m_impl->mediaControl->Stop();

    if (m_impl->sampleGrabber)
        m_impl->sampleGrabber->SetCallback(nullptr, 0);

    if (m_impl->callback) {
        m_impl->callback->Release();
        m_impl->callback = nullptr;
    }

    safeRelease(m_impl->mediaControl);
    safeRelease(m_impl->nullRenderer);
    safeRelease(m_impl->sampleGrabber);
    safeRelease(m_impl->sampleGrabberFilter);
    safeRelease(m_impl->captureFilter);
    safeRelease(m_impl->captureBuilder);
    safeRelease(m_impl->graph);
    m_impl->running = false;

    if (m_impl->comInitialized) {
        CoUninitialize();
        m_impl->comInitialized = false;
    }
}

bool DShowCapture::isRunning() const
{
    return m_impl && m_impl->running;
}

#else

DShowCapture::DShowCapture() {}
DShowCapture::~DShowCapture() {}

QList<DShowVideoInput> DShowCapture::enumerateInputs()
{
    return {};
}

bool DShowCapture::start(const QString&, const QString&, const std::function<void(const QImage&)>&, QString* errorOut)
{
    if (errorOut) *errorOut = "DirectShow disponivel apenas no Windows.";
    return false;
}

void DShowCapture::stop() {}

bool DShowCapture::isRunning() const
{
    return false;
}

#endif
