[![Hex version](https://img.shields.io/hexpm/v/rclex.svg "Hex version")](https://hex.pm/packages/rclex_experimental)
[![API docs](https://img.shields.io/hexpm/v/rclex.svg?label=hexdocs "API docs")](https://hexdocs.pm/rclex_experimental/readme.html)
[![License](https://img.shields.io/hexpm/l/rclex.svg)](https://github.com/FelixPe/rclex/blob/main/LICENSE)
[![ci-latest](https://github.com/FelixPe/rclex/actions/workflows/ci-latest.yml/badge.svg)](https://github.com/FelixPe/rclex/actions/workflows/ci-latest.yml)
[![ci-all_version](https://github.com/FelixPe/rclex/actions/workflows/ci-all_version.yml/badge.svg)](https://github.com/FelixPe/rclex/actions/workflows/ci-all_version.yml)

[日本語のREADME](README_ja.md)

# Rclex (Experimental)

Rclex is a ROS 2 client library for the functional language [Elixir](https://elixir-lang.org/).

This library lets you perform basic ROS 2 behaviors by calling out from Elixir code into the RCL (ROS Client Library) API, which
uses the ROS 2 common hierarchy.

Additionally, publisher-subscriber (PubSub) communication between nodes and associated callback functions are executed as Erlang lightweight processes.
This enables the creation of and communication between a large number of fault-tolerant
nodes while suppressing memory load.

This library is **experimental** and intended for evaluating new features. For the stable release, see [Rclex](https://hex.pm/packages/rclex).

## What is ROS 2

ROS 2 (Robot Operating System 2) is a state-of-the-art Robot development platform. In ROS 2, each functional
unit is exposed as a node, and by combining these nodes you can create different robot applications. Additionally,
communication between nodes uses a PubSub model where publishers and subscribers exchange information by specifying a
common topic name.

The main benefits of ROS 2 are that the DDS (Data Distribution Service) protocol was adopted for
communication, and the library was divided into a hierarchical structure.
This allows us to develop  ROS 2 client libraries in various languages and, of course, to build robot applications in Elixir.

For details on ROS 2, see [the official ROS 2 Documentation](https://docs.ros.org/en/rolling/index.html).

## Recommended environment

### Native environment

The basic and recommended environment is where the host (development) and the target (operation) are the same.

Currently, we use the following environment as the main development target:

- Ubuntu 24.04 LTS (Noble Numbat)
- ROS 2 Jazzy Jalisco
- Elixir v1.19.0
- Erlang/OTP 28.1

We highly recommend using [Humble Hawksbill](https://docs.ros.org/en/rolling/Releases/Release-Humble-Hawksbill.html) for ROS 2 LTS distribution.
We also confirmed the operation of this library with [Jazzy Jalisco](https://docs.ros.org/en/rolling/Releases/Release-Jazzy-Jalisco.html). See details in [PR#361](https://github.com/rclex/rclex/pull/361).
 
We do not support ROS 2 Distributions that have already reached EOL in the development of the latest version. The last supported releases are as follows.
 
- Foxy Fitzroy: [v0.11.3](https://github.com/rclex/rclex/releases/tag/v0.11.3)
- Galactic Geochelone: [v0.11.3](https://github.com/rclex/rclex/releases/tag/v0.11.3)
- Iron Irwini: [v0.11.3](https://github.com/rclex/rclex/releases/tag/v0.11.3)

For other environments used to check the operation of this library,
please refer to [here](https://github.com/rclex/rclex_docker#available-versions-docker-tags).

### Docker environment

The pre-built Docker images are available at [Docker Hub](https://hub.docker.com/r/rclex/rclex_docker).
You can also try the power of Rclex with it easily. Please check ["Docker Environment"](#Docker-environment) section for details.

### Nerves device (target)

`rclex` can be operated onto Nerves. In this case, you do not need to prepare the ROS 2 environment on the host computer to build Nerves project (so awesome!).

Please refer to [Use on Nerves](USE_ON_NERVES.md) section and [b5g-ex/rclex_on_nerves](https://github.com/b5g-ex/rclex_on_nerves) example repository for more details!

## Features

Currently, the Rclex API allows for the following:

1. Create a large number of publishers sending to the same topic.
2. Create large numbers of each combination of publishers, topics, and subscribers.
3. Create service servers and service clients
4. Create action servers and action clients
5. Basic Parameters support on nodes
6. Optional graph monitoring via telemetry events

You can find the API documentation at [https://hexdocs.pm/rclex](https://hexdocs.pm/rclex).

Please refer [rclex/rclex_examples](https://github.com/rclex/rclex_examples) for the examples of usage along with the sample code.

## Graph Monitor

`Rclex.GraphMonitor` is an optional GenServer that watches the ROS 2 graph guard
condition for a node and emits `:telemetry` events whenever nodes join or leave
the graph.

### Enabling

Pass `graph_monitor: true` when starting a node:

```elixir
Rclex.start_node("my_node", graph_monitor: true)
```

Add `:telemetry` to your project dependencies in `mix.exs`:

```elixir
{:telemetry, "~> 1.0"}
```

### Telemetry events

| Event | Measurements | Metadata |
|---|---|---|
| `[:rclex, :graph, :node_joined]` | `%{count: 1}` | `%{node_name: String.t(), node_namespace: String.t()}` |
| `[:rclex, :graph, :node_left]`   | `%{count: 1}` | `%{node_name: String.t(), node_namespace: String.t()}` |

### Attaching a handler

```elixir
:telemetry.attach_many(
  "my-graph-handler",
  [
    [:rclex, :graph, :node_joined],
    [:rclex, :graph, :node_left]
  ],
  fn event, _measurements, metadata, _config ->
    IO.puts("#{inspect(event)}: #{metadata.node_namespace}#{metadata.node_name}")
  end,
  nil
)
```

`graph_monitor: true` is independent of `:graph_change_callback`. Both options can
be set on the same node at the same time.

## Todos

- Check for an integration with [BEAM Bots](https://github.com/beam-bots/bb)
- Parameter client
- Lifecycle node & Lifecycle client
- Livebook support (ROS2 type generation needs to be considered)
- eVision integration
- TF2 support

## How to use

This section explains the quickstart for `rclex` in the native environment where ROS 2 and Elixir have been installed.

### Create the project

First of all, create the Mix project as a normal Elixir project.

```
mix new rclex_usage
cd rclex_usage
```

### Install rclex

`rclex` is [available in Hex](https://hex.pm/docs/publish).

You can install this package into your project
by adding `rclex` to your list of dependencies in `mix.exs`:

```elixir
  defp deps do
    [
      ...
      {:rclex, "~> 0.12.0"},
      ...
    ]
  end
```

After that, execute `mix deps.get` into the project repository.

```
mix deps.get
```

### Setup the ROS 2 environment

```
source /opt/ros/humble/setup.bash
```

## Configure ROS 2 types you want to use

Rclex provides pub/sub-based topic communication using the message type defined in ROS 2. Please refer [here](https://docs.ros.org/en/humble/Concepts/Basic/About-Interfaces.html) for more details about message types in ROS 2.

The message types you want to use in your project can be specified in `ros2_message_types` in `config/config.exs`, service types can be specified in `ros2_service_types` in `config/config.exs` and action types can be specified in `ros2_action_types` in `config/config.exs`. 
Multiple types can be specified separated by comma `,`.


The following `config/config.exs` example wants to use `String` message type, `SetBool` service type and `LookupTransform` action type.

```elixir
import Config

config :rclex,
  ros2_message_types: [
    "std_msgs/msg/String"
  ],
  ros2_service_types: [
    "std_srvs/srv/SetBool"
  ],
  ros2_action_types: [
    "tf2_msgs/action/LookupTransform"
  ]
```

Then, execute the following Mix task to generate required definitions and files for message types.

```
mix rclex.gen
```

When editing `config/config.exs` to change the types, do `mix rclex.gen` again.

### Write Rclex code

Now, you can acquire the environment for [Rclex API](https://hexdocs.pm/rclex/api-reference.html)! Of course, you can execute APIs on IEx directly.

Here is the simplest implementation example `lib/rclex_usage.ex` that will publish the string to `/chatter` topic.

```elixir
defmodule RclexUsage do
  alias Rclex.Pkgs.StdMsgs

  def publish_message do
    Rclex.start_node("talker")
    Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "talker")

    data = "Hello World from Rclex!"
    msg = struct(StdMsgs.Msg.String, %{data: data})

    IO.puts("Rclex: Publishing: #{data}")
    Rclex.publish(msg, "/chatter", "talker")
  end
end
```

Please also check the examples for Rclex.

- [rclex/rclex_examples](https://github.com/rclex/rclex_examples)

### Build and Execute

Build your application as follows.

```
mix compile
iex -S mix
```

Operate the following command on IEx.

```
iex()> RclexUsage.publish_message
Rclex: Publishing: Hello World from Rclex!
:ok
```

You can confirm the above operation by subscribing with `ros2 topic echo` from the other terminal.

```
$ source /opt/ros/humble/setup.bash
$ ros2 topic echo /chatter std_msgs/msg/String
data: Hello World from Rclex!
---
```

## Using Rclex from Livebook

Rclex is a NIF whose C sources are partly *generated* from the message/service/action
types you declare in application config. With a few extra steps the same workflow
works inside a [Livebook](https://livebook.dev) notebook via `Mix.install/2`.

### 1. Start Livebook with the ROS 2 environment sourced

The `Makefile` requires `ROS_DISTRO`, and the NIF links against libraries under
`/opt/ros/<distro>/lib`. These must be visible to the shell that launches Livebook,
because `Mix.install` inherits its environment when invoking `make`:

```
source /opt/ros/humble/setup.bash
livebook server
```

If Livebook is started from a desktop launcher or a systemd unit, wrap it so the
same `source` happens first — otherwise compilation halts with
`ROS_DISTRO is not defined`.

### 2. Install Rclex with the type config

`mix rclex.gen` reads `Application.get_env(:rclex, :ros2_message_types, ...)` etc.
With `Mix.install/2`, supply that via the `:config` option, just like
`config/config.exs`:

```elixir
Mix.install(
  [
    {:rclex, github: "FelixPe/rclex"}
  ],
  config: [
    rclex: [
      ros2_message_types: ["std_msgs/msg/String", "geometry_msgs/msg/Twist"],
      ros2_service_types: ["std_srvs/srv/SetBool"],
      ros2_action_types: ["tf2_msgs/action/LookupTransform"]
    ]
  ]
)
```

After this cell runs, `deps/rclex` exists inside the `Mix.install` build directory
and the NIF has been built — but only with the *base* C sources. The message
types you listed have not been generated yet.

### 3. Run `mix rclex.gen` and reload Rclex

`Mix.Tasks.Rclex.Gen` detects when it runs as a dependency and writes generated
files into `deps/rclex/src/pkgs/...` and `deps/rclex/lib/rclex/pkgs/...`, then
force-recompiles the NIF with the new sources. In the **next cell**:

```elixir
Mix.Task.run("rclex.gen", [])

# Reload so the freshly generated Rclex.Pkgs.* modules are picked up.
Application.stop(:rclex)
Application.unload(:rclex)
Application.ensure_all_started(:rclex)
```

You can now use the API normally:

```elixir
alias Rclex.Pkgs.StdMsgs

Rclex.start_node("livebook_talker")
Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "livebook_talker")

Rclex.publish(
  struct(StdMsgs.Msg.String, %{data: "Hello from Livebook!"}),
  "/chatter",
  "livebook_talker"
)
```

### Notes

- Run `Mix.install/2` and `Mix.Task.run("rclex.gen", [])` in **separate cells**.
  Triggering `deps.compile --force` from inside the same cell that is still
  finalizing `Mix.install` can deadlock the compile lock.
- If you change the configured types, edit the `:config` map, reconnect the
  notebook runtime, and rerun both cells. `Mix.install` invalidates its cache
  when the config map changes.
- The dynamic loader needs `/opt/ros/<distro>/lib` on `LD_LIBRARY_PATH` at BEAM
  start time, which is why sourcing `setup.bash` *before* launching Livebook
  (step 1) matters more than any `system_env` set inside the notebook.
- On non-host targets (e.g. Nerves) the generator looks under
  `rootfs_overlay/opt/ros/$ROS_DISTRO`; for Livebook on a workstation, leave
  `MIX_TARGET` unset so it defaults to `host`.

## Enhance devepoment experience

This section describes the information mainly for developers.

### Docker environment

This repository provides a `docker compose` environment for library development with Docker.

As mentioned above, pre-built Docker images are available at [Docker Hub](https://hub.docker.com/r/rclex/rclex_docker), which can be used to easily try out Rclex.
You can set the environment variable `$RCLEX_DOCKER_TAG` to the version of the target environment. Please refer to [here](https://github.com/rclex/rclex_docker#available-versions-docker-tags) for the available environments.

```
# optional: set to the target environment (default `latest`)
export RCLEX_DOCKER_TAG=latest
# create and start the container
docker compose up -d
# execute the container (with the workdir where this repository is mounted)
docker compose exec -w /root/rclex rclex_docker /bin/bash
# stop the container
docker compose down
```

In [GitHub Actions](https://github.com/rclex/rclex/actions), we perform CI on multiple tool versions at Pull Requests by using these Docker environments. However, we cannot guarantee operation in all of these environments.

### Automatic execution of mix test, etc.

`mix test.watch` is introduced to automatically run unit test `mix test` and code formatting `mix format` every time the source code was edited.

```
$ mix test.watch
# or, run on docker by following
$ docker compose run --rm -w /root/rclex rclex_docker mix test.watch
```

### Debugging


### Address Sanitization

Address sanitizing is a helpful technique to detect memory access errors in the NIF part of the rclex.


1. Build OTP from source and emulator with asan support
```
git clone https://github.com/erlang/otp otp_src_28.0.1
cd otp_src_28.0.1
export ERL_TOP=`pwd`    # Assuming bash/sh
./configure --prefix=/usr/local
make
sudo make install
export TYPE=asan
(cd $ERL_TOP/erts/emulator && make $TYPE)
```

2. Set asan options

```
export ASAN_OPTIONS="log_path=/tmp/asan/log"
export LSAN_OPTIONS="suppressions=$ERL_TOP/erts/emulator/asan/suppress"
```

3. The ERTS_INCLUDE_DIR might be need to set manually in the Makefile, as this variable is set by mix and might point to the wrong OTP installation.
4. To build with asan support beside debugging support two parameters need to be given to the compiler in the CFLAGS variable.

```
export CFLAGS="-fsanitize=address -fsanitize-recover=address -fno-omit-frame-pointer -g"
export LDFLAGS="-fsanitize=address"
mix compile
```

5. Elixir need to be told to use the emulator with asan support by using the erl parameter.

```
elixir --erl "-emu_type asan" -v
# or by setting the ERL_AFLAGS accordingly
ASAN_OPTIONS="verify_asan_link_order=0 log_path=./asan/log" ERL_AFLAG="-emu_type asan" mix -v
```


### Confirmation of communication operation

To check the operation, especially for communication features of this library, we prepare [rclex/rclex_connection_tests](https://github.com/rclex/rclex_connection_tests) to test the communication with the nodes implemented with Rclcpp.

```
cd /path/to/yours
git clone https://github.com/rclex/rclex
git clone https://github.com/rclex/rclex_connection_tests
cd /path/to/yours/rclex_connection_tests
./run-all.sh
```

## Presentations

- Rclex on Nerves: a bare minimum runtime platform for ROS 2 nodes in Elixir
  - [ROSCon 2023](https://roscon.ros.org/2023/)
  - [Video](https://vimeo.com/879001529/b23eaacae8) | [SpeakerDeck](https://speakerdeck.com/takasehideki/rclex-on-nerves-a-bare-minimum-runtime-platform-for-ros-2-nodes-in-elixir)
- On the way to achieve autonomous node communication in the Elixir ecosystem
  - [Code BEAM America 2022](https://codebeamamerica.com/archives/CBA_2023/index.html) at 2022/11/03
  - [Video](https://www.youtube.com/watch?v=Y4IASAU4Bjo) | [SpeakerDeck](https://speakerdeck.com/takasehideki/on-the-way-to-achieve-autonomous-node-communication-in-the-elixir-ecosystem)
- Rclex: A Library for Robotics meet Elixir
  - [Code BEAM America 2021](https://codesync.global/conferences/code-beam-sf-2021/) at 2021/11/05
  - [Video](https://www.youtube.com/watch?v=9B5lQ3kQ_wI) | [SlideShare](https://www.slideshare.net/takasehideki/rclex-a-library-for-robotics-meet-elixir)

## Maintainers and developers (including past)

- [@takasehideki](https://github.com/takasehideki)
- [@s-hosoai](https://github.com/s-hosoai)
- [@pojiro](https://github.com/pojiro)
- [@HiroiImanishi](https://github.com/HiroiImanishi)
- [@kebus426](https://github.com/kebus426)
- [@shiroro466](https://github.com/shiroro466)
- [@FelixPe](https://github.com/FelixPe)
