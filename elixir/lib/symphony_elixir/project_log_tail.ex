defmodule SymphonyElixir.ProjectLogTail do
  @moduledoc """
  Read the last N lines from a text file (best-effort; reads full file when small).
  """

  @max_full_read_bytes 5 * 1024 * 1024
  @tail_window_bytes 256 * 1024

  @spec tail_lines(Path.t(), pos_integer()) :: [String.t()]
  def tail_lines(path, n) when is_binary(path) and is_integer(n) and n > 0 do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_full_read_bytes ->
        case File.read(path) do
          {:ok, content} -> split_tail(content, n)
          {:error, _} -> []
        end

      {:ok, %{size: size}} ->
        read_tail_window(path, size, n)

      {:error, _} ->
        []
    end
  end

  defp split_tail(content, n) when is_binary(content) do
    content
    |> String.trim_trailing("\n")
    |> String.split("\n")
    |> then(fn lines ->
      len = length(lines)
      Enum.take(lines, -min(n, max(len, 1)))
    end)
  end

  defp read_tail_window(path, size, n) do
    start = max(size - @tail_window_bytes, 0)
    len = size - start

    case :file.open(String.to_charlist(path), [:read, :raw, :binary]) do
      {:ok, fd} ->
        try do
          case :file.pread(fd, start, len) do
            {:ok, bin} when is_binary(bin) ->
              split_tail(bin, n)

            _ ->
              []
          end
        after
          :file.close(fd)
        end

      {:error, _} ->
        []
    end
  end
end
