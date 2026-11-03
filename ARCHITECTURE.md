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
one ETS buffer registry for direct concurrent name-to-resource lookup. Listener
and broadcaster metadata, clock bindings and monitored asynchronous requests
live in GenServer state. Buffer creation/destruction and transport start/stop
are serialized through that process, including transport cleanup during buffer
destruction. Failed transport starts return errors without restarting the registry.
Each registry entry holds a NIF resource owning one installed ROS 2 C++
`tf2::BufferCore`. Transform history, interpolation, graph
traversal and composition are native; there is no Elixir cache or math fallback.

An internal cleanup process is started immediately before the registry. It retains each
native resource before the registry can publish it, records endpoint-start
intentions and owns final delivery of accepted asynchronous replies. It monitors
the registry independently, so an untrappable registry exit still invalidates
retained native handles, stops old transport and fails pending waits with
`{:error, :tf2_shutdown}`. The next registry generation waits for that cleanup
before creating its ETS table or accepting new buffers. Buffers and transport
are explicitly recreated after restart; history is not restored.

Graceful termination traps supervisor shutdown and also explicitly destroys native
resources before other cleanup. Clock registrations are removed explicitly on
graceful exit and by their owner monitors on abrupt exit. The registry monitors
its cleanup owner; if that process fails, the registry closes reachable native
resources and restarts. The cleanup child's shutdown budget is unlimited so
native teardown cannot be interrupted by a supervisor timeout. The NIF destructor
remains a final fallback, not the normal restart-cleanup mechanism.

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

## Robot Descriptions

`Rclex.Urdf` parses immutable string-keyed robot models, retaining topology and
common visual/collision/inertial metadata. Its pure kinematics layer computes
joint-relative transforms; TF2 remains responsible for composing chains and
storing time-varying poses. The design is inspired by James Harton's URDF work
in [Beam Bots](https://github.com/beam-bots/bb), without depending on BB's DSL.

`Rclex.Urdf.Xacro` optionally invokes the official ROS Xacro executable to expand
macros, arguments, nested includes and package references before plain URDF
parsing. It uses direct argv, inherited/per-call environment, bounded output and
execution deadlines. Xacro is trusted executable configuration, not sandboxed XML.

`Rclex.RobotStatePublisher` is explicitly supervised by the consuming application,
not an application-wide singleton. It converts JointState updates into generated
transform messages and uses existing `Rclex.Tf2` broadcasters. Fixed joints are
sent in one retained static batch. The worker owns its dedicated node by default;
borrowed-node mode requires existing TF publishers and cleans up only its own
JointState subscription. Reading live poses remains the existing TF2 listener /
buffer workflow, without mutating the URDF model or adding a second pose cache.
See [tf2.md](tf2.md#urdf-and-xacro) for supported features and lifecycle semantics.
