// Lock-free single-producer / single-consumer ring buffer.
// Safe across the two cores as long as only one context pushes and one pops.
// (Where several contexts on the same core push, wrap the push in a spinlock.)
#pragma once
#include <stdint.h>
#include <atomic>
#include "esp_attr.h"

template <typename T, uint32_t N>
class Ring {
  static_assert((N & (N - 1)) == 0, "Ring size must be a power of two");
public:
  inline bool IRAM_ATTR push(T v) {
    uint32_t h = head.load(std::memory_order_relaxed);
    if (h - tail.load(std::memory_order_acquire) >= N) return false;
    buf[h & (N - 1)] = v;
    head.store(h + 1, std::memory_order_release);
    return true;
  }
  inline bool IRAM_ATTR pop(T &v) {
    uint32_t t = tail.load(std::memory_order_relaxed);
    if (t == head.load(std::memory_order_acquire)) return false;
    v = buf[t & (N - 1)];
    tail.store(t + 1, std::memory_order_release);
    return true;
  }
  inline bool IRAM_ATTR empty() const {
    return head.load(std::memory_order_acquire) == tail.load(std::memory_order_acquire);
  }
  inline bool IRAM_ATTR full() const {
    return head.load(std::memory_order_acquire) - tail.load(std::memory_order_acquire) >= N;
  }
  inline uint32_t IRAM_ATTR count() const {
    return head.load(std::memory_order_acquire) - tail.load(std::memory_order_acquire);
  }
  // Only call from the consumer side.
  inline void IRAM_ATTR clear() { tail.store(head.load(std::memory_order_acquire), std::memory_order_release); }
private:
  T buf[N];
  std::atomic<uint32_t> head{0};
  std::atomic<uint32_t> tail{0};
};
