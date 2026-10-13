defmodule Mix.Tasks.Rclex.Prep.Ros2 do
  @shortdoc "Prepare ROS 2 resources under .ros2 directory."
  @moduledoc """
  #{@shortdoc}

  ```
  mix rclex.prep.ros2 --arch ARCH [--image IMAGE] [--ros-prefix PATH] [--install-prefix PATH]
  ```

  ROS 2 resources will be prepared under .ros2.

  An `--arch` option may be specified. Supported values are `arm64v8`, `amd64`, and `arm32v7`.

  Project defaults can be configured in `config/config.exs` and overridden by command-line options:

  ```elixir
  config :rclex, :ros2_prep,
    image: "my/ros:jazzy",
    ros_prefix: "/opt/ros/jazzy",
    install_prefix: "/ros2_ws/install",
    copy_openssl: false
  ```

  The `:image`, `:ros_prefix`, `:install_prefix`, and `:copy_openssl` values are optional. Without
  overrides, the task uses its architecture- and distro-specific defaults and copies OpenSSL libraries
  for backwards compatibility. Install prefixes may be merged or isolated.

  ## Examples

  specify arch explicitly with `--arch` option

  ```
  mix rclex.prep.ros2 --arch arm64v8
  ```

  For Nerves, `export MIX_TARGET=[TARGET]` is invoked properly, `--arch` option is not needed.

  ```
  mix rclex.prep.ros2
  ```

  For an amd64 Nerves target using Jazzy and a custom workspace image:

  ```
  mix rclex.prep.ros2 --image my/ros:jazzy --ros-prefix /opt/ros/jazzy --install-prefix /ros2_ws/install --no-copy-openssl
  ```
  """

  use Mix.Task

  @arm64v8_ros_distros ["humble", "jazzy"]
  @amd64_ros_distros ["humble", "jazzy"]
  @arm32v7_ros_distros ["humble", "jazzy"]
  @supported_ros_distros %{
    "arm64v8" => @arm64v8_ros_distros,
    "amd64" => @amd64_ros_distros,
    "arm32v7" => @arm32v7_ros_distros
  }
  @supported_arch Map.keys(@supported_ros_distros)

  @nerves_target_arch_map %{
    "rpi4" => "arm64v8",
    "rpi3" => "arm32v7",
    "x86_64" => "amd64",
    "x86_64_rt" => "amd64"
  }

  @switches [
    arch: :string,
    image: :string,
    ros_prefix: :string,
    install_prefix: :string,
    copy_openssl: :boolean
  ]

  @doc false
  def run(args) do
    if not command_exists?("docker") do
      Mix.raise("""
      Please install docker command first, we need it.
      """)
    end

    parsed_args = parse_args(args)

    arch =
      Keyword.get(
        parsed_args,
        :arch,
        Map.get(@nerves_target_arch_map, System.get_env("MIX_TARGET"))
      )

    if arch not in @supported_arch do
      Mix.raise("""
      Please select and specify the appropriate --arch from the following.
      #{Enum.join(@supported_arch, ", ")}
      """)
    end

    ros_distro = System.get_env("ROS_DISTRO")
    supported_ros_distros = supported_ros_distros(arch)

    if ros_distro not in supported_ros_distros do
      Mix.raise("""
      Please set the appropriate ROS_DISTRO from the following.
      #{Enum.join(supported_ros_distros, ", ")}
      """)
    end

    config = Application.get_env(:rclex, :ros2_prep, [])
    options = resolve_options(parsed_args, config, System.get_env("MIX_TARGET"), ros_distro)
    dest_dir_path = copy_dest_dir_path(arch, ros_distro)

    message = """
    Are you sure to copy ROS 2 resources to following directory?
    path: #{dest_dir_path}
    """

    if Mix.shell().yes?(String.trim_trailing(message)) do
      copy_from_docker!(
        dest_dir_path,
        arch,
        ros_distro,
        options.image,
        options.ros_prefix,
        options.install_prefix,
        options.copy_openssl
      )
    end
  end

  @doc false
  def command_exists?(command) when is_binary(command) do
    case System.cmd("sh", ["-c", "command -v #{command}"]) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc false
  def parse_args(args) do
    {parsed_args, _remaining_args, _invalid} = OptionParser.parse(args, strict: @switches)

    parsed_args
  end

  @doc false
  def resolve_options(cli_options, project_config, mix_target, ros_distro) do
    project_config =
      if is_map(project_config), do: Map.to_list(project_config), else: project_config

    options = Keyword.merge(project_config, cli_options)
    arch = Keyword.get(options, :arch, Map.get(@nerves_target_arch_map, mix_target))

    %{
      arch: arch,
      ros_distro: ros_distro,
      image: Keyword.get(options, :image) || ros_docker_image_tag(arch, ros_distro),
      ros_prefix: Keyword.get(options, :ros_prefix, default_ros_prefix(arch, ros_distro)),
      install_prefix: Keyword.get(options, :install_prefix, default_install_prefix(arch)),
      copy_openssl: Keyword.get(options, :copy_openssl, true)
    }
  end

  @doc false
  def supported_ros_distros(arch), do: Map.get(@supported_ros_distros, arch, [])

  @doc false
  def ros_resource_paths(ros_prefix, install_prefix) do
    [ros_prefix, install_prefix]
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(fn prefix ->
      Enum.map(["include", "lib", "share"], &Path.join(prefix, &1)) ++
        Enum.map(["include", "lib", "share"], &Path.join(prefix, "*/#{&1}"))
    end)
  end

  @doc false
  def docker_copy_args(image, dest_path, source_patterns) do
    copy_script = """
    set -e
    for pattern in "$@"; do
      mapfile -t matches < <(compgen -G "$pattern" || true)
      for source in "${matches[@]}"; do
        cp -rf "$source" /mnt/
      done
    done
    """

    [
      "run",
      "--rm",
      "-v",
      "#{dest_path}:/mnt",
      "--entrypoint",
      "bash",
      image,
      "-c",
      copy_script,
      "bash"
    ] ++ source_patterns
  end

  @doc false
  def copy_from_docker!(dest_dir_path, arch, ros_distro) do
    copy_from_docker!(
      dest_dir_path,
      arch,
      ros_distro,
      ros_docker_image_tag(arch, ros_distro),
      default_ros_prefix(arch, ros_distro),
      default_install_prefix(arch),
      true
    )
  end

  def copy_from_docker!(dest_dir_path, arch, ros_distro, image, ros_prefix, install_prefix) do
    copy_from_docker!(dest_dir_path, arch, ros_distro, image, ros_prefix, install_prefix, true)
  end

  def copy_from_docker!(
        dest_dir_path,
        arch,
        ros_distro,
        image,
        ros_prefix,
        install_prefix,
        copy_openssl
      ) do
    dest_path = Path.join(dest_dir_path, "/opt/ros/#{ros_distro}")
    create_resources_directory!(dest_path, _git_ignore = true)
    copy_ros_resources_from_docker!(dest_path, image, ros_prefix, install_prefix)

    dest_path = Path.join(dest_dir_path, "/opt/ros/#{ros_distro}/lib")
    create_resources_directory!(dest_path, _git_ignore = false)
    copy_vendor_resources_from_docker!(dest_path, image, arch, ros_distro, copy_openssl)
  end

  defp copy_ros_resources_from_docker!(dest_path, image, ros_prefix, install_prefix) do
    source_patterns = ros_resource_paths(ros_prefix, install_prefix)
    copy_from_docker_impl!(image, source_patterns, dest_path)
  end

  defp copy_vendor_resources_from_docker!(dest_path, image, arch, ros_distro, copy_openssl) do
    copy_from_docker_impl!(image, vendor_resources(arch, ros_distro, copy_openssl), dest_path)
  end

  defp vendor_resources(arch, distro, copy_openssl) do
    vendor_resource_paths(arch, distro, copy_openssl)
  end

  @doc false
  def vendor_resource_paths(arch, distro, copy_openssl) when distro in ["humble", "jazzy"] do
    dir_name = arch_dir_name(arch)

    base_resources = [
      "/lib/#{dir_name}/libspdlog.so*",
      "/lib/#{dir_name}/libtinyxml2.so*",
      "/lib/#{dir_name}/libfmt.so*",
      "/usr/lib/#{dir_name}/libyaml-0.so*",
      "/usr/lib/#{dir_name}/libyaml.so*",
      "/opt/ros/#{distro}/opt/zenoh_cpp_vendor/lib/libzenohc.so*"
    ]

    if copy_openssl do
      base_resources ++
        [
          "/lib/#{dir_name}/libssl.so*",
          "/lib/#{dir_name}/libcrypto.so*"
        ]
    else
      base_resources
    end
  end

  defp copy_from_docker_impl!(image, source_patterns, dest_path) do
    with true <- File.exists?(dest_path) do
      {_, 0} = System.cmd("docker", docker_copy_args(image, dest_path, source_patterns))
    end
  end

  defp default_ros_prefix(arch, ros_distro) when arch in ["arm64v8", "amd64"],
    do: "/opt/ros/#{ros_distro}"

  defp default_ros_prefix(_arch, _ros_distro), do: nil

  defp default_install_prefix("arm32v7"), do: "/ros2_ws/install"
  defp default_install_prefix(_arch), do: nil

  @doc false
  def ros_docker_image_tag(arch, ros_distro)

  # refs. https://hub.docker.com/r/arm64v8/ros
  def ros_docker_image_tag("arm64v8", ros_distro) when ros_distro in @arm64v8_ros_distros do
    "arm64v8/ros:#{ros_distro}-ros-core"
  end

  # refs. https://hub.docker.com/r/amd64/ros
  def ros_docker_image_tag("amd64", ros_distro) when ros_distro in @amd64_ros_distros do
    "amd64/ros:#{ros_distro}-ros-core"
  end

  def ros_docker_image_tag("arm32v7", ros_distro) when ros_distro in @arm32v7_ros_distros do
    "rclex/arm32v7_ros_docker_with_vendor_resources:#{ros_distro}"
  end

  defp arch_dir_name("arm64v8"), do: "aarch64-linux-gnu"
  defp arch_dir_name("amd64"), do: "x86_64-linux-gnu"
  defp arch_dir_name("arm32v7"), do: "arm-linux-gnueabihf"

  @doc false
  @spec create_resources_directory!(directory_path :: String.t(), gitignore :: boolean()) :: :ok
  def create_resources_directory!(directory_path, git_ignore) do
    File.mkdir_p!(directory_path)

    if git_ignore do
      gitignore_content = """
      # generated by `mix rclex.prep.ros2`
      *
      !.gitignore
      """

      File.write!(Path.join(directory_path, ".gitignore"), gitignore_content)
    end
  end

  defp copy_dest_dir_path(path \\ File.cwd!(), arch, ros_distro) do
    if Mix.target() == :host do
      Path.join(path, ".ros2/resources/from-docker/#{arch}/#{ros_distro}")
    else
      Path.join(path, "rootfs_overlay")
    end
  end
end
