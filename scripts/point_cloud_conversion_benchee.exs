# Isolates struct<->tuple conversion cost from actual NIF/rcl work for PointCloud,
# whose `points` field recursively converts a list of Point32 structs.
#
# Usage: mix run scripts/point_cloud_conversion_benchee.exs
alias Rclex.Pkgs.SensorMsgs
alias Rclex.Pkgs.GeometryMsgs
alias Rclex.Pkgs.StdMsgs

build_point_cloud = fn n ->
  %SensorMsgs.Msg.PointCloud{
    header: %StdMsgs.Msg.Header{frame_id: "map"},
    points: for(i <- 1..n, do: %GeometryMsgs.Msg.Point32{x: i * 1.0, y: i * 2.0, z: i * 3.0}),
    channels: [%SensorMsgs.Msg.ChannelFloat32{name: "intensity", values: for(i <- 1..n, do: i * 1.0)}]
  }
end

inputs =
  for n <- [10, 100, 1_000, 10_000], into: %{} do
    struct = build_point_cloud.(n)
    {"n=#{n}", %{struct: struct, tuple: SensorMsgs.Msg.PointCloud.to_tuple(struct)}}
  end

Benchee.run(
  %{
    "to_tuple/1 (struct -> tuple, pre-send)" => fn %{struct: struct} ->
      SensorMsgs.Msg.PointCloud.to_tuple(struct)
    end,
    "to_struct/1 (tuple -> struct, post-receive)" => fn %{tuple: tuple} ->
      SensorMsgs.Msg.PointCloud.to_struct(tuple)
    end,
    "full set!/2 (to_tuple + NIF decode into rcl msg)" => {
      fn %{struct: struct, message: message} ->
        SensorMsgs.Msg.PointCloud.set!(message, struct)
        message
      end,
      before_each: fn input -> Map.put(input, :message, SensorMsgs.Msg.PointCloud.create!()) end,
      after_each: fn message -> SensorMsgs.Msg.PointCloud.destroy!(message) end
    },
    "full get!/1 (NIF encode from rcl msg + to_struct)" => {
      fn %{message: message} ->
        SensorMsgs.Msg.PointCloud.get!(message)
        message
      end,
      before_each: fn %{struct: struct} = input ->
        message = SensorMsgs.Msg.PointCloud.create!()
        SensorMsgs.Msg.PointCloud.set!(message, struct)
        Map.put(input, :message, message)
      end,
      after_each: fn message -> SensorMsgs.Msg.PointCloud.destroy!(message) end
    }
  },
  inputs: inputs,
  time: 3,
  warmup: 1,
  memory_time: 2
)
