#include <cmath>
#include <cstdint>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "interop_generated.h"

namespace {

bool close_enough(double actual, double expected) {
  return std::abs(actual - expected) < 0.000001;
}

}  // namespace

int main(int argc, char **argv) {
  if (argc != 2) return 2;

  std::ifstream input(argv[1], std::ios::binary);
  std::vector<uint8_t> buffer{
      std::istreambuf_iterator<char>(input),
      std::istreambuf_iterator<char>()};

  if (!RootBufferHasIdentifier(buffer.data())) return 4;

  const Root *root = GetRoot(buffer.data());
  if (!root->active()) return 5;
  if (root->count() != UINT32_C(4000000000)) return 6;
  if (!close_enough(root->score(), 1.25)) return 7;
  if (root->mood() != Mood_CURIOUS) return 8;

  const Position *position = root->position();
  if (position == nullptr) return 9;
  if (!close_enough(position->x(), 1.5)) return 10;
  if (!close_enough(position->y(), -2.25)) return 11;
  if (!close_enough(position->z(), 3.75)) return 12;

  if (root->name() == nullptr || root->name()->str() != "interoperable") return 13;

  const auto *values = root->values();
  if (values == nullptr || values->size() != 3) return 14;
  if (values->Get(0) != -2 || values->Get(1) != 0 || values->Get(2) != 3) return 15;

  const Child *child = root->child();
  if (child == nullptr || child->id() != 7) return 16;
  if (child->label() == nullptr || child->label()->str() != "nested") return 17;

  return 0;
}
