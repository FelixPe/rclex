defmodule Rclex.Urdf.XacroTest do
  use ExUnit.Case, async: true

  alias Rclex.Urdf.Xacro

  @ros_prefix System.get_env("AMENT_PREFIX_PATH", "")
              |> String.split(":", trim: true)
              |> Enum.find(&File.regular?(Path.join([&1, "lib", "xacro", "xacro"])))
  @xacro System.find_executable("xacro") ||
           if(@ros_prefix, do: Path.join([@ros_prefix, "lib", "xacro", "xacro"]))

  setup do
    directory =
      Path.join(System.tmp_dir!(), "rclex xacro test #{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "official tool expands arguments, macros, nested includes and YAML", %{
    directory: directory
  } do
    File.mkdir_p!(Path.join(directory, "parts/nested"))
    write(directory, "parts/nested/dimensions.yaml", "length: 2.5\n")

    write(directory, "parts/nested/link.xacro", """
    <robot xmlns:xacro="http://www.ros.org/wiki/xacro">
      <xacro:property name="dimensions" value="${xacro.load_yaml('dimensions.yaml')}" lazy_eval="false"/>
      <xacro:macro name="segment" params="name">
        <link name="${name}"><visual><geometry><box size="${dimensions['length']} 1 1"/></geometry></visual></link>
      </xacro:macro>
    </robot>
    """)

    write(directory, "parts/outer.xacro", """
    <robot xmlns:xacro="http://www.ros.org/wiki/xacro">
      <xacro:include filename="nested/link.xacro"/>
    </robot>
    """)

    source =
      write(directory, "robot with spaces.xacro", """
      <robot name="example" xmlns:xacro="http://www.ros.org/wiki/xacro">
        <xacro:arg name="link_name" default="base"/>
        <xacro:include filename="parts/outer.xacro" ns="parts"/>
        <xacro:if value="true"><xacro:parts.segment name="$(arg link_name)"/></xacro:if>
        <xacro:unless value="true"><link name="must_not_exist"/></xacro:unless>
      </robot>
      """)

    assert {:ok, xml} = Xacro.expand_file(source, mappings: %{"link_name" => "arm with spaces"})
    assert xml =~ ~s(name="arm with spaces")
    assert xml =~ ~s(size="2.5 1 1")
    refute xml =~ "<xacro:"
    refute xml =~ "must_not_exist"
    assert {:ok, default_xml} = Xacro.expand_file(source)
    assert default_xml =~ ~s(name="base")
  end

  test "official package lookup uses the supplied ament environment", %{directory: directory} do
    prefix = Path.join(directory, "fake prefix")
    File.mkdir_p!(Path.join(prefix, "share/ament_index/resource_index/packages"))
    File.mkdir_p!(Path.join(prefix, "share/example_robot"))
    write(prefix, "share/ament_index/resource_index/packages/example_robot", "")

    write(
      prefix,
      "share/example_robot/link.xacro",
      ~s(<robot><link name="package_link"/></robot>)
    )

    source =
      write(directory, "package.xacro", """
      <robot name="example" xmlns:xacro="http://www.ros.org/wiki/xacro">
        <xacro:include filename="$(find example_robot)/link.xacro"/>
      </robot>
      """)

    overlay = Path.join(directory, "overlay")
    File.mkdir_p!(Path.join(overlay, "share/ament_index/resource_index/packages"))
    File.mkdir_p!(Path.join(overlay, "share/example_robot"))
    write(overlay, "share/ament_index/resource_index/packages/example_robot", "")

    write(
      overlay,
      "share/example_robot/link.xacro",
      ~s(<robot><link name="overlay_link"/></robot>)
    )

    assert {:ok, xml} =
             Xacro.expand_file(source, env: %{"AMENT_PREFIX_PATH" => prefix <> ":" <> overlay})

    assert xml =~ ~s(name="package_link")

    assert {:ok, xml} =
             Xacro.expand_file(source, env: %{"AMENT_PREFIX_PATH" => overlay <> ":" <> prefix})

    assert xml =~ ~s(name="overlay_link")
  end

  test "resolves xacro through AMENT_PREFIX_PATH when PATH has no xacro", %{directory: directory} do
    source = write(directory, "robot.xacro", "<robot name=\"example\"/>")

    assert {:ok, _} =
             Xacro.expand_file(source,
               env: %{"PATH" => "/usr/bin:/bin", "AMENT_PREFIX_PATH" => @ros_prefix}
             )
  end

  test "PATH resolution takes precedence over ament", %{directory: directory} do
    executable(directory, "xacro", "printf '<robot name=\"path\"/>' > \"$2\"\n")

    assert {:ok, ~s(<robot name="path"/>)} =
             Xacro.expand_file("unused", env: %{"PATH" => directory})
  end

  test "an explicit executable overrides PATH and keeps diagnostics out of XML", %{
    directory: directory
  } do
    executable =
      executable(directory, "custom xacro", """
      printf 'stdout diagnostic\n'
      printf 'stderr diagnostic\n' >&2
      printf '<robot name="clean"/>' > "$2"
      """)

    assert {:ok, ~s(<robot name="clean"/>)} =
             Xacro.expand_file("unused", xacro_executable: executable, env: %{"PATH" => ""})
  end

  test "mapping values are individual arguments without shell interpretation", %{
    directory: directory
  } do
    marker = Path.join(directory, "must not exist")
    value = "$(touch #{marker}); with spaces"
    executable = executable(directory, "argv", "printf '%s' \"$4\" > \"$2\"\n")

    assert {:ok, "name:=" <> ^value} =
             Xacro.expand_file("unused",
               xacro_executable: executable,
               mappings: %{"name" => value}
             )

    refute File.exists?(marker)
  end

  test "missing executable errors are actionable and an explicit override never falls back" do
    assert {:error, {:executable_not_found, "/missing/xacro"}} =
             Xacro.expand_file("unused", xacro_executable: "/missing/xacro")

    assert {:error, {:executable_not_found, :xacro}} =
             Xacro.expand_file("unused", env: %{"PATH" => "", "AMENT_PREFIX_PATH" => ""})
  end

  test "official expansion failures return exit status and diagnostics", %{directory: directory} do
    source = write(directory, "broken.xacro", "<robot>")

    assert {:error, {:expansion_failed, status, diagnostics}} =
             Xacro.expand_file(source, xacro_executable: @xacro)

    assert status != 0
    assert diagnostics =~ "XML parsing error"
  end

  test "missing includes and packages preserve official tool diagnostics", %{directory: directory} do
    for include <- ["absent_part.xacro", "$(find rclex_missing_test_package)/robot.xacro"] do
      source =
        write(directory, "missing.xacro", """
        <robot name="test" xmlns:xacro="http://www.ros.org/wiki/xacro">
          <xacro:include filename="#{include}"/>
        </robot>
        """)

      assert {:error, {:expansion_failed, status, diagnostics}} = Xacro.expand_file(source)
      assert status != 0
      assert diagnostics != ""
    end
  end

  test "rejects an oversized output before reading it", %{directory: directory} do
    executable = executable(directory, "large", "printf '123456789' > \"$2\"\n")

    assert {:error, {:output_too_large, 8}} =
             Xacro.expand_file("unused", xacro_executable: executable, max_output_bytes: 8)
  end

  test "accepts output exactly at the byte limit", %{directory: directory} do
    executable = executable(directory, "exact", "printf '12345678' > \"$2\"\n")

    assert {:ok, "12345678"} =
             Xacro.expand_file("unused", xacro_executable: executable, max_output_bytes: 8)
  end

  test "oversized running output triggers process and file cleanup", %{directory: directory} do
    {executable, env} = blocking_executable(directory)

    assert {:error, {:output_too_large, 8}} =
             Xacro.expand_file("unused",
               xacro_executable: executable,
               env: env,
               max_output_bytes: 8
             )

    assert_cleaned(env)
  end

  test "reports missing output separately from a successful exit", %{directory: directory} do
    executable = executable(directory, "no output", "exit 0\n")

    assert {:error, {:output_file, :enoent}} =
             Xacro.expand_file("unused", xacro_executable: executable)
  end

  test "diagnostic collection is bounded", %{directory: directory} do
    executable =
      executable(
        directory,
        "noisy",
        "while :; do printf '012345678901234567890123456789'; done\n"
      )

    assert {:error, {:diagnostics_too_large, 65_536}} =
             Xacro.expand_file("unused", xacro_executable: executable)
  end

  test "timeout kills the actual OS process and removes the private output", %{
    directory: directory
  } do
    {executable, env} = blocking_executable(directory)

    assert {:error, {:timeout, 100}} =
             Xacro.expand_file("unused", xacro_executable: executable, env: env, timeout_ms: 100)

    assert_cleaned(env)
  end

  test "caller death kills the actual OS process and removes its temporary directory", %{
    directory: directory
  } do
    {executable, env} = blocking_executable(directory)

    caller = spawn(fn -> Xacro.expand_file("unused", xacro_executable: executable, env: env) end)
    on_exit(fn -> Process.exit(caller, :kill) end)

    assert eventually(fn ->
             case File.read(env["OUTPUT_FILE"]) do
               {:ok, output} -> output != ""
               _ -> false
             end
           end)

    output = File.read!(env["OUTPUT_FILE"])
    assert Bitwise.band(File.stat!(Path.dirname(output)).mode, 0o777) == 0o700
    Process.exit(caller, :kill)
    assert eventually(fn -> cleaned?(env) end)
  end

  test "concurrent calls have distinct private output files and clean up", %{directory: directory} do
    executable = executable(directory, "concurrent", "printf '%s' \"$2\" > \"$2\"\n")

    outputs =
      1..8
      |> Task.async_stream(fn _ -> Xacro.expand_file("unused", xacro_executable: executable) end)
      |> Enum.map(fn {:ok, {:ok, output}} -> output end)

    assert length(Enum.uniq(outputs)) == 8
    assert Enum.all?(outputs, &(not File.exists?(Path.dirname(&1))))
  end

  test "invalid options return errors rather than crashing" do
    for opts <- [
          [timeout_ms: 0],
          [max_output_bytes: -1],
          [mappings: %{"name" => 3}],
          [mappings: %{"bad:=name" => "value"}],
          [env: %{"NAME" => 3}],
          [xacro_executable: 3]
        ] do
      assert {:error, {:invalid_option, _}} = Xacro.expand_file("unused", opts)
    end
  end

  defp write(directory, name, contents) do
    path = Path.join(directory, name)
    File.write!(path, contents)
    path
  end

  defp executable(directory, name, body) do
    path = write(directory, name, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o700)
    path
  end

  defp blocking_executable(directory) do
    executable =
      executable(directory, "blocking", """
      printf '%s' "$$" > "$PID_FILE"
      printf '%s' "$2" > "$OUTPUT_FILE"
      printf 'partial XML' > "$2"
      read blocked
      """)

    {executable,
     %{"PID_FILE" => Path.join(directory, "pid"), "OUTPUT_FILE" => Path.join(directory, "output")}}
  end

  defp assert_cleaned(env) do
    assert eventually(fn -> cleaned?(env) end)
  end

  defp cleaned?(env) do
    with {:ok, pid} <- File.read(env["PID_FILE"]),
         {:ok, output} <- File.read(env["OUTPUT_FILE"]) do
      not File.exists?("/proc/#{pid}") and not File.exists?(Path.dirname(output))
    else
      _ -> false
    end
  end

  defp eventually(check, attempts \\ 100)
  defp eventually(_check, 0), do: false

  defp eventually(check, attempts) do
    if check.() do
      true
    else
      receive do
      after
        10 -> eventually(check, attempts - 1)
      end
    end
  end
end
