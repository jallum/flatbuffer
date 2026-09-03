defmodule FlatbufferDialyzerConsumer.SparseSchema do
  use Flatbuffer, file: "priv/sparse_schema.fbs"
end

defmodule FlatbufferDialyzerConsumer.MinimalSchema do
  use Flatbuffer, file: "priv/minimal_schema.fbs"
end

defmodule FlatbufferDialyzerConsumer.SupportedFeatures do
  use Flatbuffer, file: "priv/supported_features.fbs"
end

defmodule FlatbufferDialyzerConsumer.SafeSupportedFeatures do
  use Flatbuffer, file: "priv/supported_features.fbs", safe: true
end

defmodule FlatbufferDialyzerConsumer.UnsupportedUnionVector do
  use Flatbuffer, file: "priv/union_vector.fbs"
end
