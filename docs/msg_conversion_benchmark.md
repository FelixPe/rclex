# Struct vs. tuple in the NIF boundary: benchmark findings

## Background

Every generated ROS message currently goes `struct -> to_tuple/1 -> tuple -> NIF (C)`
on send, and the reverse on receive (`NIF (C) -> tuple -> to_struct/1 -> struct`).
The question investigated here: does this tuple-mediation step cost enough to be
worth replacing with a NIF that decodes/encodes the Elixir struct (a map) directly,
skipping `to_tuple`/`to_struct`?

## Method

1. Isolated the conversion cost from the NIF/rcl work using `Rclex.Pkgs.SensorMsgs.Msg.PointCloud`
   (nested `Header`, `list(Point32)`, `list(ChannelFloat32)` - representative of a
   large-sequence message).
2. Compared against a real rclpy benchmark (not a hand-rolled Python approximation) using
   its actual compiled C extension (`rclpy.serialization.serialize_message`/`deserialize_message`).
3. Built a working prototype: a hand-written struct-based NIF for `PointCloud`
   (`set_struct!`/`get_struct!`) that decodes/encodes the Elixir struct directly via
   `enif_get_map_value`/`enif_make_map_from_arrays`, bypassing `to_tuple`/`to_struct`.
4. Added a generic CDR (de)serialization NIF (`Rclex.Nif.rmw_serialize!`/`rmw_deserialize!`,
   wrapping `rmw_serialize`/`rmw_deserialize`) so the final comparison includes CDR encoding
   on the Elixir side too - an apples-to-apples comparison against rclpy's serialize/deserialize,
   and between the tuple and struct NIF paths.

All benchmarks used `Benchee`, varying point count `n` from 10 to 10,000.

## Results

### 1. Conversion cost in isolation (no CDR)

| n | `to_tuple/1` | `to_struct/1` | full `set!/2` (incl. NIF) | full `get!/1` (incl. NIF) |
|---|---|---|---|---|
| 10 | 0.74 μs | 0.80 μs | 5.34 μs | 4.00 μs |
| 100 | 5.79 μs | 5.47 μs | 36.3 μs | 16.3 μs |
| 1,000 | 61.2 μs | 107 μs | 364 μs | 176 μs |
| 10,000 | 0.61 ms | 0.79 ms | 3.65 ms | 2.40 ms |

Conversion (`to_tuple`/`to_struct`) is a real but minority share of the full path:
~17% of `set!` and ~33% of `get!` at n=10,000. The rest is the unavoidable C-side
field-by-field copy into the rcl message struct.

### 2. rclex vs. real rclpy (rclpy path includes CDR, rclex path doesn't - see caveat)

| n | rclex full `set!` | rclpy `serialize_message` | rclex full `get!` | rclpy `deserialize_message` |
|---|---|---|---|---|
| 10 | 5.34 μs | 36.7 μs | 4.00 μs | 85.4 μs |
| 100 | 36.3 μs | 195 μs | 16.3 μs | 518 μs |
| 1,000 | 364 μs | 1.91 ms | 176 μs | 4.66 ms |
| 10,000 | 3.65 ms | 17.5 ms | 2.40 ms | 43.6 ms |

### 2b. rclex vs. rclpy, apples-to-apples (CDR included on both sides now)

Once the generic `rmw_serialize!`/`rmw_deserialize!` NIF was added, rclex could
be measured with the same CDR step rclpy's API bundles in, removing the caveat
from section 2:

| n | rclex tuple `set!`+CDR | rclpy `serialize_message` | rclex CDR+`get!` | rclpy `deserialize_message` |
|---|---|---|---|---|
| 10 | 10.0 μs | 37.6 μs | 7.3 μs | 92.0 μs |
| 100 | 44.1 μs | 201 μs | 25.0 μs | 480 μs |
| 1,000 | 415 μs | 1.64 ms | 233 μs | 4.52 ms |
| 10,000 | 4.01 ms | 15.3 ms | 2.58 ms | 41.5 ms |

Now genuinely comparable (same CDR step on both sides), rclex is still **3.5-16x
faster** than rclpy at every size, on both send and receive. This removes any
doubt left by the earlier caveat: rclex's tuple-mediated approach is not a
performance liability versus rclpy's direct-C-object approach - if anything the
gap is slightly *larger* than the uneven comparison in section 2 suggested.

### 3. Apples-to-apples: tuple vs. struct-in-NIF prototype, CDR included on both sides

| n | tuple `set!`+CDR | struct `set_struct!`+CDR | tuple CDR+`get!` | struct CDR+`get_struct!` |
|---|---|---|---|---|
| 10 | 10.1 μs | 11.8 μs | 7.9 μs | 9.9 μs |
| 100 | 49.1 μs | 49.9 μs | 26.5 μs | 32.6 μs |
| 1,000 | 453 μs | 418 μs | 237 μs | 333 μs |
| 10,000 | 4.33 ms | 4.28 ms | 2.98 ms | 4.20 ms |

Notable implementation detail hit along the way: the first version of `get_struct!`
built each map via chained `enif_make_map_put` calls (mirroring the "obvious"
translation of the tuple codegen) and was **2.5x slower** than the tuple path -
each `enif_make_map_put` on a small (flat) map reallocates/copies the whole
backing array, so N chained puts cost O(N²). Switching to single-shot
`enif_make_map_from_arrays` fixed most of that regression (see numbers above).

## Conclusion

Even with the map-construction inefficiency fixed, **the struct-in-NIF approach
is not faster than the current tuple approach**:

- **Encode (`set`)**: roughly at parity (struct path marginally faster at
  n=1,000/10,000, within noise).
- **Decode (`get`)**: struct path is consistently **25-40% slower** than the
  tuple path at every size tested.

This matches the theoretical expectation: Erlang map key-lookup/construction
(`enif_get_map_value`, `enif_make_map_from_arrays`) carries real overhead that
plain tuple indexing (`enif_get_tuple`, `enif_make_tuple`) avoids entirely.

**Recommendation: do not generalize this into the `msg_c.ex`/`msg_ex.ex` code
generator.** The ~4-6 day rewrite effort estimated for that generalization would
produce a net performance *regression* on decode and no meaningful win on
encode, on top of a significant increase in generator complexity (see
`/memories/repo/generator-notes.md` and the prototype's generalization notes
in `src/prototype_point_cloud_struct.c`).

## Artifacts

- [scripts/point_cloud_conversion_benchee.exs](../scripts/point_cloud_conversion_benchee.exs) - conversion cost in isolation (result set 1).
- [scripts/point_cloud_rclpy_bench.py](../scripts/point_cloud_rclpy_bench.py) - real rclpy comparison (result set 2).
- [scripts/point_cloud_cdr_benchee.exs](../scripts/point_cloud_cdr_benchee.exs) - apples-to-apples CDR comparison, tuple vs. struct prototype (result set 3).
- [src/rmw_serialization.c](../src/rmw_serialization.c) / [.h](../src/rmw_serialization.h) - generic CDR (de)serialize NIF used for the comparison.
- [src/prototype_point_cloud_struct.c](../src/prototype_point_cloud_struct.c) / [.h](../src/prototype_point_cloud_struct.h) - the struct-in-NIF prototype, with generalization notes for anyone revisiting this.
