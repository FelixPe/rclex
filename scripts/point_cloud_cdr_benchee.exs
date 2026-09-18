# Apples-to-apples comparison including CDR (de)serialization on both sides,
# and the struct-in-NIF PROTOTYPE (skips to_tuple/to_struct) vs the current
# tuple-mediated path. See src/prototype_point_cloud_struct.c and
# src/rmw_serialization.c for what's being benchmarked here.
#
# Usage: mix run scripts/point_cloud_cdr_benchee.exs
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

type_support = SensorMsgs.Msg.PointCloud.type_support!()

inputs =
  for n <- [10, 100, 1_000, 10_000], into: %{} do
    struct = build_point_cloud.(n)

    message = SensorMsgs.Msg.PointCloud.create!()
    SensorMsgs.Msg.PointCloud.set!(message, struct)
    payload = Rclex.Nif.rmw_serialize!(type_support, message)
    SensorMsgs.Msg.PointCloud.destroy!(message)

    {"n=#{n}", %{struct: struct, payload: payload}}
  end

Benchee.run(
  %{
    "tuple path: set! + rmw_serialize (struct -> tuple -> C struct -> CDR)" => {
      fn %{struct: struct, message: message} ->
        SensorMsgs.Msg.PointCloud.set!(message, struct)
        Rclex.Nif.rmw_serialize!(type_support, message)
        message
      end,
      before_each: fn input -> Map.put(input, :message, SensorMsgs.Msg.PointCloud.create!()) end,
      after_each: fn message -> SensorMsgs.Msg.PointCloud.destroy!(message) end
    },
    "tuple path: rmw_deserialize + get! (CDR -> C struct -> tuple -> struct)" => {
      fn %{payload: payload, message: message} ->
        Rclex.Nif.rmw_deserialize!(payload, type_support, message)
        SensorMsgs.Msg.PointCloud.get!(message)
        message
      end,
      before_each: fn input -> Map.put(input, :message, SensorMsgs.Msg.PointCloud.create!()) end,
      after_each: fn message -> SensorMsgs.Msg.PointCloud.destroy!(message) end
    },
    "struct path: set_struct! + rmw_serialize (struct -> C struct -> CDR, no tuple)" => {
      fn %{struct: struct, message: message} ->
        SensorMsgs.Msg.PointCloud.set_struct!(message, struct)
        Rclex.Nif.rmw_serialize!(type_support, message)
        message
      end,
      before_each: fn input -> Map.put(input, :message, SensorMsgs.Msg.PointCloud.create!()) end,
      after_each: fn message -> SensorMsgs.Msg.PointCloud.destroy!(message) end
    },
    "struct path: rmw_deserialize + get_struct! (CDR -> C struct -> struct, no tuple)" => {
      fn %{payload: payload, message: message} ->
        Rclex.Nif.rmw_deserialize!(payload, type_support, message)
        SensorMsgs.Msg.PointCloud.get_struct!(message)
        message
      end,
      before_each: fn input -> Map.put(input, :message, SensorMsgs.Msg.PointCloud.create!()) end,
      after_each: fn message -> SensorMsgs.Msg.PointCloud.destroy!(message) end
    }
  },
  inputs: inputs,
  time: 3,
  warmup: 1,
  memory_time: 2
)
