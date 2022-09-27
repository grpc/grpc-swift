#include <inttypes.h>
#include <stddef.h>

// Provided by ServerFuzzerLib.
int ServerFuzzer(const uint8_t *Data, size_t Size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  return ServerFuzzer(data, size);
}
