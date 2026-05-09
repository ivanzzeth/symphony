defmodule SymphonyElixir.LogFile do
  @moduledoc """
  Configures OTP's built-in rotating disk log handler for application logs.

  When `observability.per_project_log_files` is enabled in `symphony.yaml`, an
  additional rotating log is written under `log/<project_id>.log` for the primary
  project (mirroring the main daemon log stream).
  """

  require Logger

  @handler_id :symphony_disk_log
  @project_handler_id :symphony_project_disk_log
  @default_log_relative_path "log/symphony.log"
  @default_max_bytes 10 * 1024 * 1024
  @default_max_files 5

  @spec default_log_file() :: Path.t()
  def default_log_file do
    default_log_file(File.cwd!())
  end

  @spec default_log_file(Path.t()) :: Path.t()
  def default_log_file(logs_root) when is_binary(logs_root) do
    Path.join(logs_root, @default_log_relative_path)
  end

  @doc """
  Path for an optional per-project rotating log file alongside the main daemon log.
  """
  @spec project_log_file(String.t()) :: Path.t()
  def project_log_file(project_id) when is_binary(project_id) do
    main = Application.get_env(:symphony_elixir, :log_file, default_log_file())
    dir = main |> Path.expand() |> Path.dirname()
    Path.join(dir, "#{project_id}.log")
  end

  @spec configure() :: :ok
  def configure do
    log_file = Application.get_env(:symphony_elixir, :log_file, default_log_file())
    max_bytes = Application.get_env(:symphony_elixir, :log_file_max_bytes, @default_max_bytes)
    max_files = Application.get_env(:symphony_elixir, :log_file_max_files, @default_max_files)

    setup_disk_handler(log_file, max_bytes, max_files)
  end

  @doc """
  Called after the supervision tree is up so `primary_project_id` and process
  config are available: sets default logger metadata and optional per-project log handler.
  """
  @spec after_application_start() :: :ok
  def after_application_start do
    project_id = Application.get_env(:symphony_elixir, :primary_project_id) || "default"
    Logger.metadata(project_id: project_id)

    if per_project_log_files_enabled?() do
      setup_project_disk_handler(project_id)
    else
      :ok
    end
  end

  defp per_project_log_files_enabled? do
    SymphonyElixir.Config.process_config().observability
    |> Map.get(:per_project_log_files, false)
  end

  defp setup_disk_handler(log_file, max_bytes, max_files) do
    expanded_path = Path.expand(log_file)
    :ok = File.mkdir_p(Path.dirname(expanded_path))
    :ok = remove_existing_handler()

    case :logger.add_handler(
           @handler_id,
           :logger_disk_log_h,
           disk_log_handler_config(expanded_path, max_bytes, max_files)
         ) do
      :ok ->
        remove_default_console_handler()
        :ok

      {:error, reason} ->
        Logger.warning("Failed to configure rotating log file handler: #{inspect(reason)}")
        :ok
    end
  end

  defp setup_project_disk_handler(project_id) do
    path = project_log_file(project_id)
    expanded_path = Path.expand(path)
    :ok = File.mkdir_p(Path.dirname(expanded_path))
    max_bytes = Application.get_env(:symphony_elixir, :log_file_max_bytes, @default_max_bytes)
    max_files = Application.get_env(:symphony_elixir, :log_file_max_files, @default_max_files)

    _ = remove_project_handler()

    case :logger.add_handler(
           @project_handler_id,
           :logger_disk_log_h,
           disk_log_handler_config(expanded_path, max_bytes, max_files)
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to configure per-project log file handler: #{inspect(reason)}")
        :ok
    end
  end

  defp remove_existing_handler do
    case :logger.remove_handler(@handler_id) do
      :ok -> :ok
      {:error, {:not_found, @handler_id}} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp remove_project_handler do
    case :logger.remove_handler(@project_handler_id) do
      :ok -> :ok
      {:error, {:not_found, @project_handler_id}} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp remove_default_console_handler do
    case :logger.remove_handler(:default) do
      :ok -> :ok
      {:error, {:not_found, :default}} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp disk_log_handler_config(path, max_bytes, max_files) do
    # `Logger.Formatter.new/1` returns `{Logger.Formatter, %Logger.Formatter{}}` for OTP handlers.
    formatter =
      Logger.Formatter.new(
        format: "$time $metadata[$level] $message\n",
        metadata: [:project_id]
      )

    %{
      level: :all,
      formatter: formatter,
      config: %{
        file: String.to_charlist(path),
        type: :wrap,
        max_no_bytes: max_bytes,
        max_no_files: max_files
      }
    }
  end
end
