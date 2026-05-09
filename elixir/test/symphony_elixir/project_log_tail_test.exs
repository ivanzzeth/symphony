defmodule SymphonyElixir.ProjectLogTailTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ProjectLogTail

  test "tail_lines returns last N lines" do
    path = Path.join(System.tmp_dir!(), "symphony-plt-#{System.unique_integer([:positive])}.log")
    on_exit(fn -> _ = File.rm(path) end)

    content = Enum.map_join(1..20, "\n", &Integer.to_string/1)
    File.write!(path, content <> "\n")

    assert ProjectLogTail.tail_lines(path, 3) == ["18", "19", "20"]
  end
end
