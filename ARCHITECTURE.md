# Rclex architecture from v0.10.0

```
+-------------+     +-------------+     +-------------+     +-------------+     +--------------+
| Application +--+--+ Node's'     +--+--+ Node        +--+--+ Entities    +--+--+ Publisher    |
| Supervisor  |  |  | Supervisor  |  |  | Supervisor  |  |  | Supervisor  |  |  | GenServer    |
+-------------+  |  +-------------+  |  +-------------+  |  +-------------+  |  +--------------+
                 |                   |                   |                   |
                 |  +-------------+  |                   |  +-------------+  |  +--------------+
                 +--+ Context     |  |                   +--+ Node        |  +--+ Subscription |
                    | GenServer   |  |                      | GenServer   |  |  | GenServer    |
                    +-------------+  |                      +-------------+  |  +--------------+
                                     |                                       |
                                     |                                       |  +--------------+
                                     |                                       +--+ Timer        |
                                     |                                          | GenServer    |
                                     |                                          +--------------+
                                     |
                                     |  +-------------+     +-------------+     +--------------+
                                     +--+ Node        +--+--+ Entities    +--+--+ Publisher    |
                                        | Supervisor  |  |  | Supervisor  |  |  | GenServer    |
                                        +-------------+  |  +-------------+  |  +--------------+
                                                         |                   |
                                                         |  +-------------+  |  +--------------+
                                                         +--+ Node        |  +--+ Subscription |
                                                            | GenServer   |  |  | GenServer    |
                                                            +-------------+  |  +--------------+
                                                                             |
                                                                             |  +--------------+
                                                                             +--+ Timer        |
                                                                                | GenServer    |
                                                                                +--------------+
```

This diagram is written by https://asciiflow.com/

## Native TF2

`Rclex.Tf2` is supervised alongside the context and node supervisors. It owns
the buffer registry, serializes buffer creation/destruction and manages monitored,
cancellable asynchronous lookups. Each registry entry holds a NIF resource owning
one installed ROS 2 C++ `tf2::BufferCore`. Transform history, interpolation, graph
traversal and composition are native; there is no Elixir cache or math fallback.

Lookups and insertions access resources directly on dirty CPU schedulers.
The C++ bridge catches exceptions, preserves their messages and serializes access
with explicit destruction. Resource garbage collection runs a C++ destructor.
Frame YAML comes directly from tf2; structured diagnostics use yaml-cpp, not a
second Elixir graph. The existing latest-common-time API uses tf2's legacy
`_getLatestCommonTime` compatibility entry point, isolated in the bridge.

ROS subscriptions and publishers remain in Rclex. `/tf_static` uses transient-local
durability and `/tf` uses a 100-sample history by default. Per-topic `:tf_qos` and
`:tf_static_qos` options override defaults, as does the shared `:qos` option.
Publish all static transforms together when late listeners must receive the full
set: the publisher retains the latest TFMessage, not a second accumulated graph.

Jazzy's C++ contracts are the reference; Rolling is a comparison, not a promise of
runtime support. Clock-bound buffers clear dynamic history on backward jumps and
ROS-time activation/deactivation through `Rclex.Clock`; static transforms survive.
Direct clock NIF calls bypass this integration. Clock process replacement requires
rebinding by recreating the buffer. Wait deadlines deliberately use monotonic wall
time and therefore expire even when simulated time is paused, unlike ROS-time-based
timeout policies. Asynchronous waits recheck native lookups after data insertion,
without exposing tf2's internal transformable callback API.

`Rclex.Tf2.transform/5` delegates PointStamped, Vector3Stamped, QuaternionStamped,
PoseStamped and TransformStamped operations to `tf2_geometry_msgs::doTransform`
specializations. Elixir only adapts message shapes and preserves generated struct
types. TransformStamped child-frame metadata is retained around the native call.
Point clouds, covariance-bearing conversions and message filters are not included.
