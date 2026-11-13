#include "drop_target.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <oleidl.h>
#include <shellapi.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

// Window-wide OLE drop target.
//
// OLE finds the target by walking up from the window under the cursor, so
// registering the top-level window also covers the Flutter child view.
// Drag events go to Dart on `pdm/drop_target` (`entered`, `exited`,
// `dropped`) with the payload the source offered: file paths from
// CF_HDROP and the dragged text from CF_UNICODETEXT (a browser puts the
// link's URL there).

namespace {

constexpr char kChannelName[] = "pdm/drop_target";

std::string Utf8FromWide(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                       static_cast<int>(wide.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string utf8(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      utf8.data(), size, nullptr, nullptr);
  return utf8;
}

std::vector<std::string> ReadFilePaths(IDataObject* data) {
  std::vector<std::string> paths;
  FORMATETC etc = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (data == nullptr || FAILED(data->GetData(&etc, &medium))) {
    return paths;
  }
  if (auto drop = static_cast<HDROP>(GlobalLock(medium.hGlobal))) {
    const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < count; ++i) {
      const UINT length = DragQueryFileW(drop, i, nullptr, 0);
      std::wstring path(length + 1, L'\0');
      DragQueryFileW(drop, i, path.data(), length + 1);
      path.resize(length);
      paths.push_back(Utf8FromWide(path));
    }
    GlobalUnlock(medium.hGlobal);
  }
  ReleaseStgMedium(&medium);
  return paths;
}

// The dragged text, which a browser fills with the link's URL.
std::string ReadText(IDataObject* data) {
  FORMATETC etc = {CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1,
                   TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (data == nullptr || FAILED(data->GetData(&etc, &medium))) {
    return std::string();
  }
  std::string text;
  if (auto* chars = static_cast<const wchar_t*>(GlobalLock(medium.hGlobal))) {
    // The buffer is not guaranteed to be terminated within its size.
    const size_t capacity = GlobalSize(medium.hGlobal) / sizeof(wchar_t);
    size_t length = 0;
    while (length < capacity && chars[length] != L'\0') {
      ++length;
    }
    text = Utf8FromWide(std::wstring(chars, length));
    GlobalUnlock(medium.hGlobal);
  }
  ReleaseStgMedium(&medium);
  return text;
}

// Ref-counted IDropTarget that forwards the events to the channel.
//
// The registration lives for the process: the app has one window and it
// is never recreated, so this is not unregistered.
class DropTarget final : public IDropTarget {
 public:
  DropTarget(flutter::BinaryMessenger* messenger, HWND window)
      : window_(window),
        channel_(messenger, kChannelName,
                 &flutter::StandardMethodCodec::GetInstance()) {}

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }
    if (riid == IID_IUnknown || riid == IID_IDropTarget) {
      *object = static_cast<IDropTarget*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&references_);
  }
  ULONG STDMETHODCALLTYPE Release() override {
    const LONG references = InterlockedDecrement(&references_);
    if (references == 0) {
      delete this;
    }
    return references;
  }

  // IDropTarget
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data, DWORD, POINTL,
                                      DWORD* effect) override {
    const bool has_data =
        HasFormat(data, CF_HDROP) || HasFormat(data, CF_UNICODETEXT);
    if (has_data && !entered_) {
      entered_ = true;
      channel_.InvokeMethod("entered", nullptr);
    }
    // COPY only: the app reads the payload and must never let the source
    // believe the drag was a move (a move would delete the original).
    *effect = has_data ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL, DWORD* effect) override {
    *effect = entered_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragLeave() override {
    if (entered_) {
      entered_ = false;
      channel_.InvokeMethod("exited", nullptr);
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD, POINTL,
                                 DWORD* effect) override {
    entered_ = false;
    if (data == nullptr) {
      *effect = DROPEFFECT_NONE;
      return S_OK;
    }

    auto args = std::make_unique<flutter::EncodableValue>(
        flutter::EncodableMap{});
    auto& map = std::get<flutter::EncodableMap>(*args);

    flutter::EncodableList files;
    for (const auto& path : ReadFilePaths(data)) {
      files.emplace_back(path);
    }
    map[flutter::EncodableValue("files")] = flutter::EncodableValue(files);

    // Windows reports no URIs, only CF_HDROP and text; `uris` stays empty
    // and the Dart side reads the link out of `text`.
    map[flutter::EncodableValue("uris")] =
        flutter::EncodableValue(flutter::EncodableList{});

    const std::string text = ReadText(data);
    if (!text.empty()) {
      map[flutter::EncodableValue("text")] = flutter::EncodableValue(text);
    }

    channel_.InvokeMethod("dropped", std::move(args));
    *effect = DROPEFFECT_COPY;
    return S_OK;
  }

 private:
  ~DropTarget() = default;

  static bool HasFormat(IDataObject* data, CLIPFORMAT format) {
    FORMATETC etc = {format, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    return data != nullptr && data->QueryGetData(&etc) == S_OK;
  }

  LONG references_ = 1;
  HWND window_;
  bool entered_ = false;
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};

bool g_attached = false;

}  // namespace

void drop_target_attach(flutter::BinaryMessenger* messenger, HWND window) {
  if (window == nullptr || messenger == nullptr || g_attached) {
    return;
  }
  // OLE needs an apartment on this UI thread. STA matches the window's
  // message loop; S_FALSE means COM was already set up.
  OleInitialize(nullptr);

  auto* target = new DropTarget(messenger, window);
  if (FAILED(RegisterDragDrop(window, target))) {
    target->Release();
    return;
  }
  g_attached = true;
}
