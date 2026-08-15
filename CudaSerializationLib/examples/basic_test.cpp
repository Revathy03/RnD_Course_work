#include <iostream>
#include <cstring>
#include <cassert>

// Host-side serialization primitives for testing

struct HostSizeArchive {
    size_t size = 0;

    template<typename T>
    void serialize(const T& val) {
        size += sizeof(T);
    }

    void serialize(const char* s) {
        size += sizeof(uint32_t);
        size += std::strlen(s);
    }
};

struct HostOutputArchive {
    uint8_t* buffer;
    size_t offset = 0;

    HostOutputArchive(void* ptr) : buffer((uint8_t*)ptr) {}

    template<typename T>
    void serialize(const T& val) {
        std::memcpy(buffer + offset, &val, sizeof(T));
        offset += sizeof(T);
    }

    void serialize(const char* s) {
        uint32_t len = std::strlen(s);
        std::memcpy(buffer + offset, &len, sizeof(uint32_t));
        offset += sizeof(uint32_t);
        if (len > 0) {
            std::memcpy(buffer + offset, s, len);
        }
        offset += len;
    }
};

struct HostInputArchive {
    const uint8_t* buffer;
    size_t offset = 0;

    HostInputArchive(const void* ptr) : buffer((const uint8_t*)ptr) {}

    template<typename T>
    void serialize(T& val) {
        std::memcpy(&val, buffer + offset, sizeof(T));
        offset += sizeof(T);
    }

    void serialize(char* s) {
        uint32_t len;
        std::memcpy(&len, buffer + offset, sizeof(uint32_t));
        offset += sizeof(uint32_t);
        if (len > 0) {
            std::memcpy(s, buffer + offset, len);
        }
        s[len] = '\0';
        offset += len;
    }
};

// Test Data Structure
struct TestRecord {
    int id;
    float value;
    char name[16];
};

void test_basic_serialization() {
    std::cout << "[Test] Basic Serialization on CPU\n";
    
    // Create test record
    TestRecord original;
    original.id = 42;
    original.value = 3.14f;
    std::strcpy(original.name, "TestRecord");

    // Calculate size
    HostSizeArchive sizer;
    sizer.serialize(original.id);
    sizer.serialize(original.value);
    sizer.serialize(original.name);

    std::cout << "  Size: " << sizer.size << " bytes\n";
    assert(sizer.size > 0);

    // Serialize
    uint8_t buffer[256];
    HostOutputArchive out(buffer);
    out.serialize(original.id);
    out.serialize(original.value);
    out.serialize(original.name);

    std::cout << "  Serialized: " << out.offset << " bytes\n";

    // Deserialize
    TestRecord restored;
    HostInputArchive in(buffer);
    in.serialize(restored.id);
    in.serialize(restored.value);
    in.serialize(restored.name);

    // Verify
    assert(restored.id == original.id);
    assert(restored.value == original.value);
    assert(std::strcmp(restored.name, original.name) == 0);

    std::cout << "  ✓ Verified: ID=" << restored.id 
              << ", Value=" << restored.value 
              << ", Name=" << restored.name << "\n";
}

void test_multiple_records() {
    std::cout << "\n[Test] Multiple Records Serialization\n";

    TestRecord originals[3];
    for (int i = 0; i < 3; ++i) {
        originals[i].id = 100 + i;
        originals[i].value = 1.0f + i;
        std::sprintf(originals[i].name, "Rec_%d", i);
    }

    // Compute total size
    size_t totalSize = 0;
    for (int i = 0; i < 3; ++i) {
        HostSizeArchive sizer;
        sizer.serialize(originals[i].id);
        sizer.serialize(originals[i].value);
        sizer.serialize(originals[i].name);
        totalSize += sizer.size;
    }
    std::cout << "  Total size for 3 records: " << totalSize << " bytes\n";

    // Serialize all
    uint8_t buffer[512];
    size_t offsets[3];
    size_t currentOffset = 0;

    for (int i = 0; i < 3; ++i) {
        offsets[i] = currentOffset;
        HostOutputArchive out((void*)(buffer + currentOffset));
        out.serialize(originals[i].id);
        out.serialize(originals[i].value);
        out.serialize(originals[i].name);
        currentOffset += out.offset;
    }

    // Deserialize and verify
    TestRecord restored[3];
    for (int i = 0; i < 3; ++i) {
        HostInputArchive in((const void*)(buffer + offsets[i]));
        in.serialize(restored[i].id);
        in.serialize(restored[i].value);
        in.serialize(restored[i].name);

        assert(restored[i].id == originals[i].id);
        assert(restored[i].value == originals[i].value);
        assert(std::strcmp(restored[i].name, originals[i].name) == 0);

        std::cout << "  ✓ Record " << i << ": ID=" << restored[i].id 
                  << ", Value=" << restored[i].value 
                  << ", Name=" << restored[i].name << "\n";
    }
}

int main() {
    std::cout << "=== CPU-side Serialization Verification ===\n\n";

    test_basic_serialization();
    test_multiple_records();

    std::cout << "\n=== All Tests Passed! ===\n";
    return 0;
}
