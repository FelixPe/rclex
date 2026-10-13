defmodule Mix.Tasks.Rclex.Prep.Ros2Test do
  use ExUnit.Case

  alias Mix.Tasks.Rclex.Prep.Ros2

  test "parses configurable image and prefix switches" do
    assert Ros2.parse_args([
             "--image",
             "custom/ros:j azy",
             "--ros-prefix",
             "/opt/ros/jazzy",
             "--install-prefix",
             "/ros2_ws/install",
             "--no-copy-openssl"
           ]) == [
             image: "custom/ros:j azy",
             ros_prefix: "/opt/ros/jazzy",
             install_prefix: "/ros2_ws/install",
             copy_openssl: false
           ]
  end

  describe "resolve_options/4" do
    test "command-line values override project configuration" do
      options =
        Ros2.resolve_options(
          [
            image: "cli/ros:jazzy",
            ros_prefix: "/cli/ros",
            install_prefix: "/cli/install",
            copy_openssl: false
          ],
          [
            image: "project/ros:jazzy",
            ros_prefix: "/project/ros",
            install_prefix: "/project/install",
            copy_openssl: true
          ],
          "x86_64_rt",
          "jazzy"
        )

      assert options == %{
               arch: "amd64",
               ros_distro: "jazzy",
               image: "cli/ros:jazzy",
               ros_prefix: "/cli/ros",
               install_prefix: "/cli/install",
               copy_openssl: false
             }
    end

    test "uses amd64 and architecture-specific defaults when overrides are absent" do
      assert Ros2.resolve_options([], [], "x86_64", "humble") == %{
               arch: "amd64",
               ros_distro: "humble",
               image: "amd64/ros:humble-ros-core",
               ros_prefix: "/opt/ros/humble",
               install_prefix: nil,
               copy_openssl: true
             }

      assert Ros2.resolve_options([], [], "rpi3", "humble") == %{
               arch: "arm32v7",
               ros_distro: "humble",
               image: "rclex/arm32v7_ros_docker_with_vendor_resources:humble",
               ros_prefix: nil,
               install_prefix: "/root/ros2_ws/install",
               copy_openssl: true
             }
    end
  end

  describe "supported_ros_distros/1" do
    test "supports Jazzy on every supported architecture" do
      assert Ros2.supported_ros_distros("amd64") == ["humble", "jazzy"]
      assert Ros2.supported_ros_distros("arm64v8") == ["humble", "jazzy"]
      assert Ros2.supported_ros_distros("arm32v7") == ["humble", "jazzy"]

      assert Ros2.ros_docker_image_tag("arm32v7", "jazzy") ==
               "rclex/arm32v7_ros_docker_with_vendor_resources:jazzy"
    end
  end

  describe "ros_resource_paths/2" do
    test "copies the global include tree and isolated workspace package include trees" do
      assert Ros2.ros_resource_paths("/opt/ros/jazzy", "/ros2_ws/install") == [
               "/opt/ros/jazzy/include",
               "/opt/ros/jazzy/lib",
               "/opt/ros/jazzy/share",
               "/opt/ros/jazzy/*/include",
               "/opt/ros/jazzy/*/lib",
               "/opt/ros/jazzy/*/share",
               "/ros2_ws/install/include",
               "/ros2_ws/install/lib",
               "/ros2_ws/install/share",
               "/ros2_ws/install/*/include",
               "/ros2_ws/install/*/lib",
               "/ros2_ws/install/*/share"
             ]
    end

    test "accepts an absent optional prefix" do
      assert Ros2.ros_resource_paths("/opt/ros/jazzy", nil) == [
               "/opt/ros/jazzy/include",
               "/opt/ros/jazzy/lib",
               "/opt/ros/jazzy/share",
               "/opt/ros/jazzy/*/include",
               "/opt/ros/jazzy/*/lib",
               "/opt/ros/jazzy/*/share"
             ]
    end
  end

  describe "docker_copy_args/3" do
    test "passes the image and source patterns as distinct arguments" do
      source_patterns = ["/opt/ros/jazzy/share", "/ros2_ws/install/my_msgs/share"]

      args = Ros2.docker_copy_args("custom/ros:j azy", "/tmp/rootfs overlay", source_patterns)

      assert Enum.take(args, 7) == [
               "run",
               "--rm",
               "-v",
               "/tmp/rootfs overlay:/mnt",
               "--entrypoint",
               "bash",
               "custom/ros:j azy"
             ]

      assert List.last(args) == "/ros2_ws/install/my_msgs/share"
      assert Enum.at(args, -2) == "/opt/ros/jazzy/share"
      assert Enum.at(args, 7) == "-c"
    end
  end

  describe "vendor_resource_paths/3" do
    test "can omit OpenSSL when the Nerves system already provides it" do
      paths = Ros2.vendor_resource_paths("amd64", "jazzy", false)

      assert paths == [
               "/lib/x86_64-linux-gnu/libspdlog.so*",
               "/lib/x86_64-linux-gnu/libtinyxml2.so*",
               "/lib/x86_64-linux-gnu/libfmt.so*",
               "/lib/x86_64-linux-gnu/liblttng-ust*.so*",
               "/lib/x86_64-linux-gnu/libnuma.so.1*",
               "/usr/lib/x86_64-linux-gnu/libyaml-0.so*",
               "/usr/lib/x86_64-linux-gnu/libyaml.so*",
               "/opt/ros/jazzy/opt/zenoh_cpp_vendor/lib/libzenohc.so*"
             ]
    end

    test "includes OpenSSL when requested" do
      paths = Ros2.vendor_resource_paths("amd64", "jazzy", true)

      assert "/lib/x86_64-linux-gnu/libssl.so*" in paths
      assert "/lib/x86_64-linux-gnu/libcrypto.so*" in paths
    end
  end
end
