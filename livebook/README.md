# Rclex Livebook examples

A collection of small, self-contained [Livebook](https://livebook.dev) notebooks
that mirror the canonical ROS 2 examples.

Each notebook installs Rclex via `Mix.install/2` and runs `mix rclex.gen` to
generate the C/Elixir bindings for the message, service, and action types it
uses. See the **[Using Rclex from Livebook](../README.md#using-rclex-from-livebook)**
section of the main README for the prerequisites — in particular, you must
launch Livebook from a shell where `source /opt/ros/<distro>/setup.bash` has
been run.

| Notebook                                | Topic                              | Inspired by                                                                                                                              |
| --------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| [talker_listener.livemd](talker_listener.livemd) | `std_msgs/msg/String` pub/sub      | [`demo_nodes_cpp/talker` & `listener`](https://github.com/ros2/demos/tree/rolling/demo_nodes_cpp/src/topics)                             |
| [services.livemd](services.livemd)             | `std_srvs/srv/SetBool` server/client | [`demo_nodes_cpp/add_two_ints_*`](https://github.com/ros2/demos/tree/rolling/demo_nodes_cpp/src/services)                                |
| [parameters.livemd](parameters.livemd)         | parameters & remote ParameterClient | [`demo_nodes_cpp/parameters/parameter_blackboard`](https://github.com/ros2/demos/tree/rolling/demo_nodes_cpp/src/parameters)             |
| [tf2.livemd](tf2.livemd)                       | TF broadcaster / listener           | [`tf2_ros` tutorials](https://docs.ros.org/en/rolling/Tutorials/Intermediate/Tf2/Writing-A-Tf2-Static-Broadcaster-Cpp.html)              |
| [lifecycle.livemd](lifecycle.livemd)           | Managed (lifecycle) node            | [`demo_nodes_cpp/lifecycle/lifecycle_talker`](https://github.com/ros2/demos/tree/rolling/lifecycle)                                       |
| [clock.livemd](clock.livemd)                   | `Rclex.Clock` / `Rclex.Time`        | [`rclpy.clock`](https://github.com/ros2/rclpy/blob/rolling/rclpy/rclpy/clock.py) & [`rclcpp::Clock`](https://github.com/ros2/rclcpp/blob/rolling/rclcpp/include/rclcpp/clock.hpp) |

> **Tip.** You can verify each notebook from a separate terminal with the
> standard ROS 2 CLI tools (`ros2 topic echo`, `ros2 service call`,
> `ros2 lifecycle get`, `tf2_echo`, …).
