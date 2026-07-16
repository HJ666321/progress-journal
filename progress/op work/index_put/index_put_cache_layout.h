#ifndef INDEX_PUT_CACHE_LAYOUT_H
#define INDEX_PUT_CACHE_LAYOUT_H

#include <cstdint>

namespace aiacc {
namespace op {
namespace index_put_cache {

struct SlotInfo {
    bool valid{false};
    uint32_t block_idx{0};
    uint32_t block_offset{0};
};

struct Layout {
    uint32_t block_size{16};
    uint32_t num_heads{32};
    uint32_t head_size{128};
    uint32_t elems_per_word{8};
};

inline SlotInfo decode_slot(int64_t slot, uint32_t block_size) {
    SlotInfo info;
    if (slot < 0 || block_size == 0) return info;
    info.valid = true;
    info.block_idx = static_cast<uint32_t>(slot / static_cast<int64_t>(block_size));
    info.block_offset = static_cast<uint32_t>(slot % static_cast<int64_t>(block_size));
    return info;
}

inline uint32_t words_per_token(const Layout& layout) {
    return (layout.num_heads * layout.head_size + layout.elems_per_word - 1) /
           layout.elems_per_word;
}

inline uint32_t cache_word_offset(const Layout& layout,
                                  uint32_t block_idx,
                                  uint32_t block_offset,
                                  uint32_t head,
                                  uint32_t head_elem_word) {
    const uint32_t head_words = (layout.head_size + layout.elems_per_word - 1) /
                                layout.elems_per_word;
    return (((block_idx * layout.block_size + block_offset) * layout.num_heads + head) *
            head_words) + head_elem_word;
}

} // namespace index_put_cache
} // namespace op
} // namespace aiacc

#endif // INDEX_PUT_CACHE_LAYOUT_H
