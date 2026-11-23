#include <windows.h>
#include <xaudio2.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>

namespace {
// The helper owns one session. Only the engine error notification runs on
// an XAudio2 thread. Source buffers are consumed in submission order.
constexpr size_t kBlock = 480;  // 10 ms of interleaved stereo at 48 kHz.
constexpr size_t kSlots = 12;
constexpr size_t kPrimeBlocks = 7;
using Block = std::array<int16_t, kBlock * 2>;
std::array<Block, kSlots> slots{};
Block staging{};
size_t filled = 0, next = 0;
unsigned long long dropped = 0, submitted = 0;
unsigned underruns = 0;
CO_MTA_USAGE_COOKIE apartment = nullptr;
IXAudio2* engine = nullptr;
IXAudio2MasteringVoice* master = nullptr;
IXAudio2SourceVoice* source = nullptr;
bool started = false;
struct EngineEvents final : IXAudio2EngineCallback {
  std::atomic<HRESULT> error{S_OK};
  void STDMETHODCALLTYPE OnProcessingPassStart() override {}
  void STDMETHODCALLTYPE OnProcessingPassEnd() override {}
  void STDMETHODCALLTYPE OnCriticalError(HRESULT hr) override { error.store(hr); }
} events;
bool registered = false;

void submitBlock() {
  XAUDIO2_VOICE_STATE state{};
  source->GetState(&state, XAUDIO2_VOICE_NOSAMPLESPLAYED);
  if (state.BuffersQueued == kSlots) {
    dropped += kBlock;
    return;
  }
  if (started && state.BuffersQueued == 0) {
    ++underruns;
    const HRESULT stop = source->Stop();
    started = false;
    if (FAILED(stop)) {
      events.error.store(stop);
      return;
    }
  }
  slots[next] = staging;
  XAUDIO2_BUFFER buffer{};
  buffer.AudioBytes = static_cast<UINT32>(sizeof(Block));
  buffer.pAudioData = reinterpret_cast<const BYTE*>(slots[next].data());
  HRESULT hr = source->SubmitSourceBuffer(&buffer);
  if (SUCCEEDED(hr)) {
    next = (next + 1) % kSlots;
    submitted += kBlock;
    if (!started && state.BuffersQueued + 1 >= kPrimeBlocks) {
      hr = source->Start();
      started = SUCCEEDED(hr);
    }
  }
  if (FAILED(hr)) events.error.store(hr);
}
}  // namespace

#define API extern "C" __declspec(dllexport)
API HRESULT audio_open() {
  // Dart can resume the isolate on another thread between calls.
  HRESULT hr = CoIncrementMTAUsage(&apartment);
  if (FAILED(hr)) return hr;
  hr = XAudio2Create(&engine);
  if (FAILED(hr)) return hr;
  hr = engine->RegisterForCallbacks(&events);
  if (FAILED(hr)) return hr;
  registered = true;
  hr = engine->CreateMasteringVoice(&master);
  if (FAILED(hr)) return hr;
  WAVEFORMATEX format{};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 2;
  format.nSamplesPerSec = 48000;
  format.wBitsPerSample = 16;
  format.nBlockAlign = 4;
  format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
  return engine->CreateSourceVoice(&source, &format);
}

API HRESULT audio_set_volume(uint32_t percent) {
  if (!source || percent > 100) return E_INVALIDARG;
  return source->SetVolume(static_cast<float>(percent) / 100.0f);
}

API HRESULT audio_write(const int16_t* samples, size_t frames) {
  while (frames && SUCCEEDED(events.error.load())) {
    const size_t count = (std::min)(kBlock - filled, frames);
    std::memcpy(staging.data() + 2 * filled, samples, count * 4);
    samples += 2 * count;
    frames -= count;
    filled += count;
    if (filled == kBlock) {
      submitBlock();
      filled = 0;
    }
  }
  return events.error.load();
}

API void audio_close() {
  if (source) source->DestroyVoice();
  if (master) master->DestroyVoice();
  if (registered) engine->UnregisterForCallbacks(&events);
  if (engine) engine->Release();
  if (apartment) CoDecrementMTAUsage(apartment);
  std::fprintf(stderr, "XAudio2: frames submitted=%llu dropped=%llu underruns=%u\n",
               submitted, dropped, underruns);
}
