defmodule Rclex.UrdfTest do
  use ExUnit.Case, async: true

  alias Rclex.Urdf

  test "parses a single link robot with string names" do
    assert {:ok, model} = Urdf.parse_string(~s(<robot name="example"><link name="base"/></robot>))
    assert model.name == "example"
    assert model.root == "base"
    assert Map.has_key?(model.links, "base")
    assert model.joint_order == []
  end

  @tag :tmp_dir
  test "file API reads plain URDF and dispatches Xacro explicitly", %{tmp_dir: directory} do
    path = Path.join(directory, "robot.urdf")
    File.write!(path, ~s(<robot name="from_file"><link name="base"/></robot>))
    assert {:ok, model} = Urdf.parse_file(path)
    assert model.name == "from_file"
    assert {:error, {:invalid_format, :unknown}} = Urdf.parse_file(path, format: :unknown)

    assert {:error, {:executable_not_found, "/missing/xacro"}} =
             Urdf.parse_file(path, format: :xacro, xacro_executable: "/missing/xacro")

    assert {:error, {:executable_not_found, "/missing/xacro"}} =
             Urdf.parse_file(path <> ".xacro", xacro_executable: "/missing/xacro")

    assert {:error, :enoent} = Urdf.parse_file(path <> ".missing")
  end

  test "parses joints with URDF defaults and normalized axes" do
    assert {:ok, model} = Urdf.parse_string(robot("revolute", ~s(<axis xyz="0 0 2"/>)))
    joint = model.joints["joint"]
    assert joint.axis == {0.0, 0.0, 1.0}
    assert joint.origin == %{xyz: {0.0, 0.0, 0.0}, rpy: {0.0, 0.0, 0.0}}
    assert joint.type == :revolute
    assert model.joint_order == ["joint"]
  end

  test "retains common geometry and inertial metadata without loading meshes" do
    xml = """
    <robot name="mesh_bot"><link name="base">
      <visual><geometry><mesh filename="package://robot/mesh.stl" scale="1 2 3"/></geometry>
      <material name="paint"><color rgba="1 0 0 1"/></material></visual>
      <collision><geometry><box size="1 2 3"/></geometry></collision>
      <inertial><mass value="2"/><inertia ixx="1" iyy="2" izz="3" ixy="0" ixz="0" iyz="0"/></inertial>
    </link></robot>
    """

    assert {:ok, model} = Urdf.parse_string(xml)

    assert [%{geometry: {:mesh, %{filename: "package://robot/mesh.stl", scale: {1.0, 2.0, 3.0}}}}] =
             model.links["base"].visuals

    assert [%{geometry: {:box, %{size: {1.0, 2.0, 3.0}}}}] = model.links["base"].collisions
    assert model.links["base"].inertial.mass == 2.0
  end

  test "rejects malformed or unsafe XML and unresolved preprocessing" do
    assert {:error, _} = Urdf.parse_string("<robot>")
    assert {:error, _} = Urdf.parse_string("<not_robot/>")

    assert {:error, :dtd_not_allowed} =
             Urdf.parse_string(~s(<!DOCTYPE robot [<!ENTITY x "bad">]><robot/>))

    assert {:error, :unexpanded_xacro} =
             Urdf.parse_string(
               ~s(<robot xmlns:xacro="http://www.ros.org/wiki/xacro"><xacro:include filename="x"/></robot>)
             )

    assert {:error, _} =
             Urdf.parse_string(
               ~s(<robot name="r"><include filename="x"/><link name="base"/></robot>)
             )

    assert {:error, :unexpanded_xacro} =
             Urdf.parse_string(
               ~s(<robot name="r" xmlns:macro="http://www.ros.org/wiki/xacro"><link name="base"/><macro:include filename="x"/></robot>)
             )
  end

  test "rejects invalid topology, numeric fields and joint types" do
    for xml <- [
          ~s(<robot name="r"><link name="a"/><link name="a"/></robot>),
          ~s(<robot name="r"><link name="a"/><link name="b"/></robot>),
          String.replace(robot("fixed"), ~s(child link="tip"), ~s(child link="missing")),
          robot("invented"),
          robot("prismatic", ~s(<axis xyz="0 0 0"/>)),
          robot("prismatic", ~s(<axis xyz="1e308 1e308 1e308"/>)),
          robot("fixed", ~s(<origin xyz="1 nope 3"/>))
        ] do
      assert {:error, _} = Urdf.parse_string(xml)
    end
  end

  test "computes rotated prismatic motion after the origin transform" do
    assert {:ok, model} =
             Urdf.parse_string(
               robot("prismatic", ~s(<origin xyz="1 2 3" rpy="0 0 1.5707963267948966"/>))
             )

    stamp = %{sec: 42, nanosec: 7}

    assert {:ok, %{static: [], dynamic: [transform]}} =
             Urdf.transforms(model, %{"joint" => 2.0}, stamp, frame_prefix: "robot/")

    assert transform.header == %{frame_id: "robot/base", stamp: stamp}
    assert transform.child_frame_id == "robot/tip"
    assert_in_delta transform.transform.translation.x, 1.0, 1.0e-10
    assert_in_delta transform.transform.translation.y, 4.0, 1.0e-10
    assert_in_delta transform.transform.rotation.z, :math.sqrt(0.5), 1.0e-10
  end

  test "fixed joints are static, absent moving joints are not fabricated" do
    {:ok, moving} = Urdf.parse_string(robot("continuous"))
    assert {:ok, %{static: [], dynamic: []}} = Urdf.transforms(moving, %{}, %{sec: 0, nanosec: 0})
    {:ok, fixed} = Urdf.parse_string(robot("fixed"))

    assert {:ok, %{static: [transform], dynamic: []}} =
             Urdf.transforms(fixed, %{}, %{sec: 0, nanosec: 0})

    assert transform.transform.rotation == %{x: 0.0, y: 0.0, z: 0.0, w: 1.0}
  end

  test "resolves mimic chains irrespective of topology or supplied mimic positions" do
    xml = """
    <robot name="gripper"><link name="base"/><link name="left"/><link name="right"/><link name="third"/>
    <joint name="source" type="prismatic"><parent link="base"/><child link="left"/></joint>
    <joint name="mimic" type="prismatic"><parent link="base"/><child link="right"/><mimic joint="source" multiplier="-1" offset="0.1"/></joint>
    <joint name="chain" type="prismatic"><parent link="right"/><child link="third"/><mimic joint="mimic" multiplier="2"/></joint></robot>
    """

    {:ok, model} = Urdf.parse_string(xml)

    assert {:ok, %{dynamic: transforms}} =
             Urdf.transforms(model, %{"source" => 0.2, "mimic" => 999}, %{sec: 1, nanosec: 0})

    by_child = Map.new(transforms, &{&1.child_frame_id, &1.transform.translation.x})
    assert_in_delta by_child["right"], -0.1, 1.0e-10
    assert_in_delta by_child["third"], -0.2, 1.0e-10

    assert {:ok, %{dynamic: []}} =
             Urdf.transforms(model, %{"mimic" => 1.0}, %{sec: 1, nanosec: 0})

    assert {:error, _} =
             Urdf.parse_string(
               String.replace(xml, ~s(mimic joint="source"), ~s(mimic joint="chain"))
             )
  end

  test "rejects invalid transform input and explicitly unsupported multi-DOF joints" do
    {:ok, model} = Urdf.parse_string(robot("revolute"))

    for {positions, stamp, opts} <- [
          {%{"joint" => :nan}, %{sec: 1, nanosec: 0}, []},
          {%{}, %{sec: -1, nanosec: 0}, []},
          {%{}, %{sec: 0, nanosec: 1_000_000_000}, []},
          {%{}, %{sec: 0, nanosec: 0}, [frame_prefix: "/bad/"]}
        ] do
      assert {:error, _} = Urdf.transforms(model, positions, stamp, opts)
    end

    {:ok, floating} = Urdf.parse_string(robot("floating"))

    assert {:error, {:unsupported_joint, "joint", :floating}} =
             Urdf.transforms(floating, %{}, %{sec: 0, nanosec: 0})
  end

  defp robot(type, extra \\ "") do
    """
    <robot name="test"><link name="base"/><link name="tip"/>
    <joint name="joint" type="#{type}"><parent link="base"/><child link="tip"/>#{extra}</joint></robot>
    """
  end
end
