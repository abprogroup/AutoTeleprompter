#include "windows_mic_volume.h"

#include <windows.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <objbase.h>
#include <propidl.h>
#include <propkeydef.h>
#include <propsys.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <string>

namespace {

// PKEY_Device_FriendlyName ({a45c254e-df1c-4efd-8020-67d146a850e0}, 14)
constexpr PROPERTYKEY kPkeyDeviceFriendlyName = {
    {0xa45c254e, 0xdf1c, 0x4efd,
     {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}},
    14};

class ScopedComInit {
 public:
  ScopedComInit() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr)) {
      should_uninit_ = true;
      ok_ = true;
    } else if (hr == RPC_E_CHANGED_MODE) {
      ok_ = true;
    }
  }

  ~ScopedComInit() {
    if (should_uninit_) {
      CoUninitialize();
    }
  }

  bool ok() const { return ok_; }

 private:
  bool ok_ = false;
  bool should_uninit_ = false;
};

std::string WideToUtf8(const wchar_t* wide) {
  if (!wide || !*wide) return "";
  int len = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr,
                                nullptr);
  if (len <= 1) return "";
  std::string out(static_cast<size_t>(len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), len, nullptr, nullptr);
  return out;
}

std::string NormalizeLabel(const std::string& input) {
  std::string out;
  out.reserve(input.size());
  bool prev_space = true;
  for (unsigned char ch : input) {
    if (std::isspace(ch)) {
      if (!prev_space) {
        out.push_back(' ');
        prev_space = true;
      }
    } else {
      out.push_back(static_cast<char>(std::tolower(ch)));
      prev_space = false;
    }
  }
  if (!out.empty() && out.back() == ' ') {
    out.pop_back();
  }
  return out;
}

std::string ReadDeviceFriendlyName(IMMDevice* device) {
  if (!device) return "";
  IPropertyStore* store = nullptr;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store)) || !store) {
    return "";
  }
  PROPVARIANT var;
  PropVariantInit(&var);
  std::string name;
  if (SUCCEEDED(store->GetValue(kPkeyDeviceFriendlyName, &var))) {
    if (var.vt == VT_LPWSTR && var.pwszVal) {
      name = WideToUtf8(var.pwszVal);
    }
  }
  PropVariantClear(&var);
  store->Release();
  return name;
}

IMMDevice* ResolveCaptureEndpoint(IMMDeviceEnumerator* enumerator,
                                  const std::string& preferred_label,
                                  std::string* out_name) {
  const std::string wanted = NormalizeLabel(preferred_label);
  const bool match_by_label =
      !wanted.empty() && wanted != "system default microphone";

  if (match_by_label) {
    IMMDeviceCollection* collection = nullptr;
    if (SUCCEEDED(enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE,
                                                 &collection)) &&
        collection) {
      UINT count = 0;
      if (SUCCEEDED(collection->GetCount(&count))) {
        IMMDevice* partial_match = nullptr;
        std::string partial_name;
        for (UINT i = 0; i < count; ++i) {
          IMMDevice* candidate = nullptr;
          if (FAILED(collection->Item(i, &candidate)) || !candidate) continue;
          const std::string friendly = ReadDeviceFriendlyName(candidate);
          const std::string norm = NormalizeLabel(friendly);
          if (norm == wanted) {
            if (partial_match) partial_match->Release();
            collection->Release();
            if (out_name) *out_name = friendly;
            return candidate;
          }
          if (!partial_match && wanted.size() >= 6 && norm.size() >= 6 &&
              (norm.find(wanted) != std::string::npos ||
               wanted.find(norm) != std::string::npos)) {
            partial_match = candidate;
            partial_name = friendly;
          } else {
            candidate->Release();
          }
        }
        if (partial_match) {
          collection->Release();
          if (out_name) *out_name = partial_name;
          return partial_match;
        }
      }
      collection->Release();
    }
  }

  IMMDevice* default_device = nullptr;
  HRESULT hr =
      enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &default_device);
  if (FAILED(hr) || !default_device) {
    hr = enumerator->GetDefaultAudioEndpoint(eCapture, eCommunications,
                                             &default_device);
  }
  if (SUCCEEDED(hr) && default_device) {
    if (out_name) *out_name = ReadDeviceFriendlyName(default_device);
    return default_device;
  }
  return nullptr;
}

WindowsMicVolumeState ReadEndpointState(IAudioEndpointVolume* endpoint,
                                        const std::string& device_name) {
  WindowsMicVolumeState state;
  float scalar = 0.0f;
  BOOL muted = FALSE;
  if (FAILED(endpoint->GetMasterVolumeLevelScalar(&scalar))) {
    state.error = "Could not read microphone volume level.";
    return state;
  }
  endpoint->GetMute(&muted);
  state.available = true;
  state.volume_percent = std::clamp<int>(
      static_cast<int>(std::lround(scalar * 100.0f)), 0, 100);
  state.muted = muted != FALSE;
  state.device_name = device_name;
  return state;
}

}  // namespace

WindowsMicVolumeState GetWindowsMicVolume(const std::string& preferred_label) {
  WindowsMicVolumeState state;
  ScopedComInit com;
  if (!com.ok()) {
    state.error = "Windows audio COM initialization failed.";
    return state;
  }

  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                reinterpret_cast<void**>(&enumerator));
  if (FAILED(hr) || !enumerator) {
    state.error = "Windows audio device enumerator unavailable.";
    return state;
  }

  std::string device_name;
  IMMDevice* device =
      ResolveCaptureEndpoint(enumerator, preferred_label, &device_name);
  enumerator->Release();
  if (!device) {
    state.error = "No active Windows microphone found.";
    return state;
  }

  IAudioEndpointVolume* endpoint = nullptr;
  hr = device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(&endpoint));
  device->Release();
  if (FAILED(hr) || !endpoint) {
    state.error = "Microphone volume control is unavailable for this device.";
    return state;
  }

  state = ReadEndpointState(endpoint, device_name);
  endpoint->Release();
  return state;
}

WindowsMicVolumeState SetWindowsMicVolume(const std::string& preferred_label,
                                          int volume_percent,
                                          std::optional<bool> muted) {
  WindowsMicVolumeState state;
  ScopedComInit com;
  if (!com.ok()) {
    state.error = "Windows audio COM initialization failed.";
    return state;
  }

  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                reinterpret_cast<void**>(&enumerator));
  if (FAILED(hr) || !enumerator) {
    state.error = "Windows audio device enumerator unavailable.";
    return state;
  }

  std::string device_name;
  IMMDevice* device =
      ResolveCaptureEndpoint(enumerator, preferred_label, &device_name);
  enumerator->Release();
  if (!device) {
    state.error = "No active Windows microphone found.";
    return state;
  }

  IAudioEndpointVolume* endpoint = nullptr;
  hr = device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(&endpoint));
  device->Release();
  if (FAILED(hr) || !endpoint) {
    state.error = "Microphone volume control is unavailable for this device.";
    return state;
  }

  const int clamped = std::clamp(volume_percent, 0, 100);
  const float scalar = static_cast<float>(clamped) / 100.0f;
  hr = endpoint->SetMasterVolumeLevelScalar(scalar, nullptr);
  if (FAILED(hr)) {
    endpoint->Release();
    state.error = "Could not set Windows microphone volume.";
    return state;
  }

  if (muted.has_value()) {
    endpoint->SetMute(*muted ? TRUE : FALSE, nullptr);
  } else if (clamped > 0) {
    BOOL currently_muted = FALSE;
    if (SUCCEEDED(endpoint->GetMute(&currently_muted)) && currently_muted) {
      endpoint->SetMute(FALSE, nullptr);
    }
  }

  state = ReadEndpointState(endpoint, device_name);
  endpoint->Release();
  return state;
}
