defmodule Rclex.Urdf.Xacro do
  @moduledoc """
  Expands a source file with the official ROS Xacro executable.

  `expand_file/2` accepts these keyword options:

    * `:mappings` - a string-to-string map of Xacro argument values (default `%{}`).
    * `:xacro_executable` - a trusted executable path or name. An explicit override
      must resolve; otherwise `PATH`, then each `AMENT_PREFIX_PATH` entry's
      `lib/xacro/xacro`, are searched.
    * `:env` - a map or list of string environment keys and string values (or
      `nil` to unset a variable), overlaid on the inherited environment. The
      resulting `PATH` and `AMENT_PREFIX_PATH` also control executable lookup.
    * `:timeout_ms` - positive execution timeout, default `5000`.
    * `:max_output_bytes` - positive XML size limit, default 16 MiB.

  The executable is launched directly with individual arguments, without a
  shell. The absolute source filename is preserved for relative includes, YAML
  loading and package lookup. XML is read from a private temporary output file;
  stdout and stderr are diagnostics only, bounded to 64 KiB combined.

  Errors are `{:error, reason}` with structured reasons such as
  `{:executable_not_found, name}`, `{:invalid_option, key}`,
  `{:expansion_failed, exit_status, diagnostics}`, `{:timeout, milliseconds}`,
  `{:output_too_large, limit}`, `{:diagnostics_too_large, limit}`,
  `{:output_file, posix_reason}`, `{:temporary_directory, posix_reason}`,
  `{:spawn_failed, message}` or `{:worker_failed, reason}`.

  This is not a sandbox: trust the executable, source, includes, mappings and
  environment. Xacro can read files and evaluate expressions. Output size is
  polled while running and checked before a bounded read, not enforced as a disk
  quota. On POSIX systems, timeout or caller death kills the actual executable
  using `kill -KILL`, closes its Port and removes temporary files. Arbitrary
  descendants created by a custom executable are not supervised. Cleanup cannot
  be guaranteed if the VM or cleanup worker itself is forcibly terminated.
  """

  @diagnostic_limit 65_536
  @default_output_limit 16 * 1024 * 1024

  @spec expand_file(Path.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def expand_file(path, opts \\ []) do
    with :ok <- validate(path, opts),
         env = Map.new(Keyword.get(opts, :env, %{})),
         {:ok, executable} <- resolve(Keyword.get(opts, :xacro_executable), env),
         {:ok, kill} <- resolve_kill() do
      caller = self()
      reference = make_ref()

      {worker, monitor} =
        spawn_monitor(fn ->
          caller_monitor = Process.monitor(caller)
          Process.flag(:trap_exit, true)
          result = expand(executable, kill, Path.expand(path), opts, env, caller_monitor)
          send(caller, {reference, result})
        end)

      receive do
        {^reference, result} ->
          Process.demonitor(monitor, [:flush])
          result

        {:DOWN, ^monitor, :process, ^worker, reason} ->
          {:error, {:worker_failed, reason}}
      end
    end
  end

  defp validate(path, opts) do
    cond do
      not text?(path) or path == "" -> {:error, {:invalid_option, :path}}
      not is_list(opts) -> {:error, {:invalid_option, :options}}
      not Keyword.keyword?(opts) -> {:error, {:invalid_option, :options}}
      true -> validate_options(opts)
    end
  end

  defp validate_options(opts) do
    mappings = Keyword.get(opts, :mappings, %{})
    env = Keyword.get(opts, :env, %{})
    executable = Keyword.get(opts, :xacro_executable)

    cond do
      not positive?(Keyword.get(opts, :timeout_ms, 5000)) ->
        {:error, {:invalid_option, :timeout_ms}}

      not positive?(Keyword.get(opts, :max_output_bytes, @default_output_limit)) ->
        {:error, {:invalid_option, :max_output_bytes}}

      not valid_mappings?(mappings) ->
        {:error, {:invalid_option, :mappings}}

      not valid_env?(env) ->
        {:error, {:invalid_option, :env}}

      not valid_executable?(executable) ->
        {:error, {:invalid_option, :xacro_executable}}

      true ->
        :ok
    end
  end

  defp valid_mappings?(mappings) when is_map(mappings),
    do: Enum.all?(mappings, &valid_mapping?/1)

  defp valid_mappings?(_), do: false

  defp valid_mapping?({key, value}),
    do: text?(key) and key != "" and not String.contains?(key, [":=", "="]) and text?(value)

  defp valid_executable?(nil), do: true
  defp valid_executable?(executable), do: text?(executable) and executable != ""

  defp positive?(value), do: is_integer(value) and value > 0

  defp text?(value),
    do: is_binary(value) and String.valid?(value) and not String.contains?(value, <<0>>)

  defp valid_env?(env) when is_map(env) or is_list(env) do
    Enum.all?(env, fn
      {key, value} ->
        text?(key) and key != "" and not String.contains?(key, "=") and
          (is_nil(value) or text?(value))

      _ ->
        false
    end)
  end

  defp valid_env?(_env), do: false

  defp resolve(override, env) do
    environment = Map.merge(System.get_env(), env)

    candidates =
      if override do
        executable_candidates(override, environment)
      else
        executable_candidates("xacro", environment) ++
          for prefix <- String.split(environment["AMENT_PREFIX_PATH"] || "", ":", trim: true) do
            Path.join([prefix, "lib", "xacro", "xacro"])
          end
      end

    case Enum.find_value(candidates, &System.find_executable/1) do
      nil -> {:error, {:executable_not_found, override || :xacro}}
      executable -> {:ok, executable}
    end
  end

  defp executable_candidates(name, environment) do
    if String.contains?(name, "/") do
      [Path.expand(name)]
    else
      for directory <- String.split(environment["PATH"] || "", ":", trim: true) do
        Path.expand(Path.join(directory, name))
      end
    end
  end

  defp resolve_kill do
    case System.find_executable("kill") do
      nil -> {:error, {:executable_not_found, :kill}}
      executable -> {:ok, executable}
    end
  end

  defp expand(executable, kill, source, opts, env, caller_monitor) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "rclex-xacro-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    case File.mkdir(directory) do
      :ok ->
        try do
          with :ok <- temporary_permissions(directory) do
            output = Path.join(directory, "expanded.xml")

            mappings =
              Enum.map(Keyword.get(opts, :mappings, %{}), fn {key, value} ->
                "#{key}:=#{value}"
              end)

            args = ["-o", output, source | mappings]
            run(executable, kill, args, output, opts, env, caller_monitor)
          end
        after
          File.rm_rf(directory)
        end

      {:error, reason} ->
        {:error, {:temporary_directory, reason}}
    end
  end

  defp temporary_permissions(directory) do
    case File.chmod(directory, 0o700) do
      :ok -> :ok
      {:error, reason} -> {:error, {:temporary_directory, reason}}
    end
  end

  defp run(executable, kill, args, output, opts, env, caller_monitor) do
    timeout = Keyword.get(opts, :timeout_ms, 5000)
    limit = Keyword.get(opts, :max_output_bytes, @default_output_limit)
    deadline = System.monotonic_time(:millisecond) + timeout

    port =
      Port.open({:spawn_executable, String.to_charlist(executable)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        :hide,
        args: Enum.map(args, &String.to_charlist/1),
        env:
          Enum.map(env, fn {key, value} ->
            {String.to_charlist(key),
             if(value == nil, do: false, else: String.to_charlist(value))}
          end)
      ])

    try do
      collect(port, output, caller_monitor, deadline, timeout, limit, "")
    after
      terminate(port, kill)
    end
  rescue
    error in [ArgumentError, ErlangError] -> {:error, {:spawn_failed, Exception.message(error)}}
  end

  defp collect(port, output, monitor, deadline, timeout, limit, diagnostics) do
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      remaining <= 0 ->
        {:error, {:timeout, timeout}}

      oversized?(output, limit) ->
        {:error, {:output_too_large, limit}}

      true ->
        receive do
          {^port, {:data, data}} ->
            if byte_size(diagnostics) + byte_size(data) > @diagnostic_limit do
              {:error, {:diagnostics_too_large, @diagnostic_limit}}
            else
              collect(port, output, monitor, deadline, timeout, limit, diagnostics <> data)
            end

          {^port, {:exit_status, 0}} ->
            read_output(output, limit)

          {^port, {:exit_status, status}} ->
            {:error, {:expansion_failed, status, diagnostics}}

          {:DOWN, ^monitor, :process, _caller, _reason} ->
            {:error, :caller_down}

          {:EXIT, ^port, :normal} ->
            collect(port, output, monitor, deadline, timeout, limit, diagnostics)

          {:EXIT, ^port, reason} ->
            {:error, {:port_failed, reason}}
        after
          min(remaining, 10) ->
            collect(port, output, monitor, deadline, timeout, limit, diagnostics)
        end
    end
  end

  defp oversized?(output, limit) do
    case File.stat(output) do
      {:ok, %{size: size}} -> size > limit
      _ -> false
    end
  end

  defp read_output(output, limit) do
    if oversized?(output, limit) do
      {:error, {:output_too_large, limit}}
    else
      case :file.open(String.to_charlist(output), [:read, :binary, :raw]) do
        {:ok, file} ->
          try do
            case :file.read(file, limit + 1) do
              {:ok, xml} when byte_size(xml) <= limit -> {:ok, xml}
              {:ok, _xml} -> {:error, {:output_too_large, limit}}
              :eof -> {:ok, ""}
              {:error, reason} -> {:error, {:output_file, reason}}
            end
          after
            :file.close(file)
          end

        {:error, reason} ->
          {:error, {:output_file, reason}}
      end
    end
  end

  defp terminate(port, kill) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd(kill, ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
        if Port.info(port), do: Port.close(port)

      nil ->
        :ok
    end
  end
end
