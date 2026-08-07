import Config

config :rclex,
  ros2_message_types: [
    "std_msgs/msg/Empty",
    "std_msgs/msg/String",
    "std_msgs/msg/UInt8MultiArray",
    "std_msgs/msg/UInt32MultiArray",
    "geometry_msgs/msg/Twist",
    "tf2_msgs/msg/TFMessage",
    "sensor_msgs/msg/PointCloud",
    "sensor_msgs/msg/JointState",
    "diagnostic_msgs/msg/DiagnosticStatus",
    "action_msgs/msg/GoalInfo"
  ],
  ros2_directories: [],
  ros2_remappings: [],
  ros2_ros_args: [],
  ros2_service_types: [
    "std_srvs/srv/SetBool"
  ],
  ros2_action_types: [
    "tf2_msgs/action/LookupTransform"
  ]
