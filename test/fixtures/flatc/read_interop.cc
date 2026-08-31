#include <cmath>
#include <cstdint>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "flatbuffers/flatbuffers.h"
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

  flatbuffers::Verifier verifier(buffer.data(), buffer.size());
  if (!VerifyRootBuffer(verifier)) return 3;
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

  const ScalarMix *scalar_mix = root->scalar_mix();
  if (scalar_mix == nullptr || scalar_mix->prefix() != 1) return 18;
  if (scalar_mix->wide() != UINT64_C(72623859790382856)) return 19;
  if (scalar_mix->suffix() != 515) return 20;

  const auto *scalar_mixes = root->scalar_mixes();
  if (scalar_mixes == nullptr || scalar_mixes->size() != 2) return 21;
  if (scalar_mixes->Get(0)->prefix() != 2 || scalar_mixes->Get(0)->wide() != 17 ||
      scalar_mixes->Get(0)->suffix() != 18) return 22;
  if (scalar_mixes->Get(1)->prefix() != 3 || scalar_mixes->Get(1)->wide() != 19 ||
      scalar_mixes->Get(1)->suffix() != 20) return 23;

  const NestedMix *nested_mix = root->nested_mix();
  if (nested_mix == nullptr || nested_mix->flag() != 4) return 24;
  if (nested_mix->value().prefix() != 5 || nested_mix->value().wide() != 21 ||
      nested_mix->value().suffix() != 22) return 25;
  if (nested_mix->count() != UINT32_C(4000000001)) return 26;

  return 0;
}
