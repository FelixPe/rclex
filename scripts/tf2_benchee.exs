alias Rclex.{Nif, Tf2}

:ok = Tf2.buffer_new("benchmark", "tf2_benchmark")

transform = %{
  header: %{frame_id: "map", stamp: %{sec: 1, nanosec: 0}},
  child_frame_id: "sensor",
  transform: %{
    translation: %{x: 1.0, y: 2.0, z: 3.0},
    rotation: %{x: 0.0, y: 0.0, z: 0.0, w: 1.0}
  }
}

:ok = Tf2.set_transform_static("benchmark", transform, "benchmark", "tf2_benchmark")
[{_, resource}] = :ets.lookup(:rclex_tf2_buffers, {"benchmark", "tf2_benchmark", "/"})

try do
  Benchee.run(
    %{
      "BufferCore through NIF" => fn ->
        Nif.tf2_lookup_transform!(resource, "map", "sensor", 0)
      end,
      "Rclex.Tf2 public lookup" => fn ->
        Rclex.Tf2.lookup_transform("benchmark", "map", "sensor", 0, 0.0, "tf2_benchmark")
      end
    },
    time: 1,
    warmup: 1,
    memory_time: 1
  )
after
  Tf2.buffer_destroy("benchmark", "tf2_benchmark")
end
