defmodule Rclex.Urdf.Parser do
  @moduledoc false
  require Record
  alias Rclex.Urdf.{Joint, Model}

  Record.defrecordp(
    :element,
    :xmlElement,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :attribute,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  @types %{
    "fixed" => :fixed,
    "revolute" => :revolute,
    "continuous" => :continuous,
    "prismatic" => :prismatic,
    "floating" => :floating,
    "planar" => :planar
  }
  @max_bytes 16 * 1024 * 1024
  @numeric_fields %{
    "lower" => :lower,
    "upper" => :upper,
    "effort" => :effort,
    "velocity" => :velocity,
    "damping" => :damping,
    "friction" => :friction,
    "ixx" => :ixx,
    "iyy" => :iyy,
    "izz" => :izz,
    "ixy" => :ixy,
    "ixz" => :ixz,
    "iyz" => :iyz
  }

  def parse_string(xml) when is_binary(xml) do
    cond do
      byte_size(xml) > @max_bytes -> {:error, :description_too_large}
      not String.valid?(xml) -> {:error, :invalid_encoding}
      Regex.match?(~r/<!\s*(DOCTYPE|ENTITY)\b/i, xml) -> {:error, :dtd_not_allowed}
      true -> parse_xml(xml)
    end
  end

  defp parse_xml(xml) do
    {document, rest} =
      :xmerl_scan.string(String.to_charlist(xml),
        quiet: true,
        space: :normalize,
        namespace_conformant: true,
        fetch_fun: fn _, state -> {:error, :external_resource_not_allowed, state} end
      )

    ensure(String.trim(to_string(rest)) == "", :trailing_content)
    ensure(tag(document) == "robot", :expected_robot)
    ensure(not unexpanded?(document), :unexpanded_xacro)
    ensure(children(document, "include") == [], :nonstandard_include)
    links = indexed(children(document, "link"), &parse_link/1, :duplicate_link)
    joints = indexed(children(document, "joint"), &parse_joint/1, :duplicate_joint)
    {root, order} = topology(links, joints)
    validate_mimics(joints)
    materials = indexed(children(document, "material"), &parse_material/1, :duplicate_material)

    warnings =
      for child <- children(document),
          tag(child) not in ["link", "joint", "material"],
          do: "Ignored <#{tag(child)}> extension"

    {:ok,
     %Model{
       name: required(document, "name"),
       root: root,
       links: links,
       joints: joints,
       joint_order: order,
       materials: materials,
       warnings: warnings
     }}
  rescue
    exception in [ArgumentError, ArithmeticError, FunctionClauseError] ->
      {:error, {:invalid_urdf, Exception.message(exception)}}
  catch
    {:urdf, reason} -> {:error, reason}
    :exit, reason -> {:error, {:xml_parse_error, reason}}
  end

  defp indexed(elements, parser, error) do
    Enum.reduce(elements, %{}, fn child, acc ->
      parsed = parser.(child)
      ensure(not Map.has_key?(acc, parsed.name), {error, parsed.name})
      Map.put(acc, parsed.name, parsed)
    end)
  end

  defp parse_link(element) do
    %{
      name: required(element, "name"),
      visuals: Enum.map(children(element, "visual"), &parse_shape/1),
      collisions: Enum.map(children(element, "collision"), &parse_shape/1),
      inertial: optional(element, "inertial", &parse_inertial/1)
    }
  end

  defp parse_joint(element) do
    name = required(element, "name")
    type_name = required(element, "type")
    type = Map.get(@types, type_name)
    ensure(type != nil, {:unsupported_joint_type, name, type_name})

    axis =
      case children(element, "axis") do
        [] -> {1.0, 0.0, 0.0}
        [axis] -> vector(required(axis, "xyz"), 3)
        _ -> fail({:duplicate_element, "axis"})
      end

    {axis_x, axis_y, axis_z} = axis
    length = :math.sqrt(axis_x * axis_x + axis_y * axis_y + axis_z * axis_z)
    ensure(type == :fixed or length > 0, {:zero_axis, name})

    normalized =
      if length > 0, do: {axis_x / length, axis_y / length, axis_z / length}, else: axis

    %Joint{
      name: name,
      type: type,
      parent: required(required_child(element, "parent"), "link"),
      child: required(required_child(element, "child"), "link"),
      origin: origin(element),
      axis: normalized,
      limit: optional(element, "limit", &numeric_fields(&1, ~w(lower upper effort velocity))),
      dynamics: optional(element, "dynamics", &numeric_fields(&1, ~w(damping friction))),
      mimic:
        optional(element, "mimic", fn mimic ->
          %{
            joint: required(mimic, "joint"),
            multiplier: number(attr(mimic, "multiplier", "1")),
            offset: number(attr(mimic, "offset", "0"))
          }
        end)
    }
  end

  defp origin(parent) do
    optional(parent, "origin", fn element ->
      %{
        xyz: vector(attr(element, "xyz", "0 0 0"), 3),
        rpy: vector(attr(element, "rpy", "0 0 0"), 3)
      }
    end) || %{xyz: {0.0, 0.0, 0.0}, rpy: {0.0, 0.0, 0.0}}
  end

  defp parse_shape(element) do
    %{
      name: attr(element, "name"),
      origin: origin(element),
      geometry: optional(element, "geometry", &parse_geometry/1),
      material: optional(element, "material", &parse_material/1)
    }
  end

  defp parse_geometry(element) do
    case children(element) do
      [shape] ->
        case tag(shape) do
          "mesh" ->
            {:mesh,
             %{
               filename: required(shape, "filename"),
               scale: vector(attr(shape, "scale", "1 1 1"), 3)
             }}

          "box" ->
            {:box, %{size: vector(required(shape, "size"), 3)}}

          "sphere" ->
            {:sphere, %{radius: number(required(shape, "radius"))}}

          "cylinder" ->
            {:cylinder,
             %{
               radius: number(required(shape, "radius")),
               length: number(required(shape, "length"))
             }}

          other ->
            fail({:unsupported_geometry, other})
        end

      _ ->
        fail(:invalid_geometry)
    end
  end

  defp parse_material(element) do
    %{
      name: attr(element, "name"),
      color: optional(element, "color", &vector(required(&1, "rgba"), 4)),
      texture: optional(element, "texture", &required(&1, "filename"))
    }
  end

  defp parse_inertial(element) do
    %{
      origin: origin(element),
      mass: optional(element, "mass", &number(required(&1, "value"))),
      inertia: optional(element, "inertia", &numeric_fields(&1, ~w(ixx iyy izz ixy ixz iyz)))
    }
  end

  defp numeric_fields(element, fields) do
    Map.new(fields, fn field ->
      value = attr(element, field)
      {Map.fetch!(@numeric_fields, field), if(value, do: number(value))}
    end)
  end

  defp topology(links, joints) do
    ensure(map_size(links) > 0, :no_links)

    parents =
      Enum.reduce(joints, %{}, fn {name, joint}, acc ->
        ensure(Map.has_key?(links, joint.parent), {:missing_link, joint.parent})
        ensure(Map.has_key?(links, joint.child), {:missing_link, joint.child})
        ensure(not Map.has_key?(acc, joint.child), {:multiple_parents, joint.child})
        Map.put(acc, joint.child, name)
      end)

    roots = Map.keys(links) -- Map.keys(parents)
    ensure(length(roots) == 1, {:invalid_roots, Enum.sort(roots)})
    [root] = roots
    adjacency = joints |> Map.values() |> Enum.group_by(& &1.parent)
    {visited, order} = walk(root, adjacency, MapSet.new(), [])
    ensure(MapSet.size(visited) == map_size(links), :disconnected_or_cyclic_tree)
    {root, Enum.reverse(order)}
  end

  @spec walk(String.t(), %{String.t() => [Joint.t()]}, MapSet.t(String.t()), [String.t()]) ::
          {MapSet.t(String.t()), [String.t()]}
  defp walk(link, adjacency, visited, order) do
    ensure(not MapSet.member?(visited, link), {:cycle, link})

    Enum.reduce(
      Enum.sort_by(Map.get(adjacency, link, []), & &1.name),
      {MapSet.put(visited, link), order},
      fn joint, {seen, names} -> walk(joint.child, adjacency, seen, [joint.name | names]) end
    )
  end

  defp validate_mimics(joints) do
    Enum.each(joints, fn {name, _joint} -> mimic_chain(name, joints, []) end)
  end

  @spec mimic_chain(String.t(), %{String.t() => Joint.t()}, [String.t()]) :: nil
  defp mimic_chain(name, joints, seen) do
    ensure(name not in seen, {:mimic_cycle, name})
    joint = Map.fetch!(joints, name)

    if joint.mimic do
      source = Map.get(joints, joint.mimic.joint)
      ensure(source != nil, {:missing_mimic_joint, joint.mimic.joint})
      angular = [:revolute, :continuous]

      ensure(
        (joint.type in angular and source.type in angular) or
          (joint.type == :prismatic and source.type == :prismatic),
        {:invalid_mimic_type, name}
      )

      mimic_chain(source.name, joints, [name | seen])
    end
  end

  defp vector(value, size) do
    parts = String.split(value)
    ensure(length(parts) == size, {:invalid_vector, value})
    parts |> Enum.map(&number/1) |> List.to_tuple()
  end

  defp number(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> fail({:invalid_number, value})
    end
  end

  defp unexpanded?(element) do
    xacro_namespace =
      case element(element, :expanded_name) do
        {namespace, _name} -> to_string(namespace) == "http://www.ros.org/wiki/xacro"
        _ -> false
      end

    xacro_namespace or String.starts_with?(tag(element), "xacro:") or
      Enum.any?(element(element, :attributes), fn attribute ->
        value = attribute(attribute, :value) |> to_string()
        String.contains?(value, ["${", "$("])
      end) or Enum.any?(children(element), &unexpanded?/1)
  end

  defp required_child(parent, name) do
    optional(parent, name, & &1) || fail({:missing_element, name})
  end

  defp optional(parent, name, parser) do
    case children(parent, name) do
      [] -> nil
      [child] -> parser.(child)
      _ -> fail({:duplicate_element, name})
    end
  end

  defp required(element, name) do
    value = attr(element, name)

    ensure(
      is_binary(value) and String.trim(value) != "",
      {:missing_attribute, tag(element), name}
    )

    value
  end

  defp attr(element, name, default \\ nil) do
    Enum.find_value(element(element, :attributes), default, fn attribute ->
      if to_string(attribute(attribute, :name)) == name,
        do: to_string(attribute(attribute, :value))
    end)
  end

  defp children(parent),
    do: Enum.filter(element(parent, :content), &Record.is_record(&1, :xmlElement))

  defp children(parent, name), do: Enum.filter(children(parent), &(tag(&1) == name))
  defp tag(element), do: to_string(element(element, :name))
  defp ensure(true, _reason), do: :ok
  defp ensure(false, reason), do: fail(reason)
  defp fail(reason), do: throw({:urdf, reason})
end
