defmodule Kmk.ClientTest do
  use ExUnit.Case
  setup do
    {:ok, client} = Kmk.Client.start_link("ws://127.0.0.1:7777")
    {:ok, %{client: client}}
  end

  test "ping", c do
    :pong = c[:client] |> Kmk.Client.ping
    100 |> :timer.sleep
  end

  test "put and get", c do
    :ok = c[:client] |> Kmk.Client.put("foo", 123)
    {:ok, 123} = c[:client] |> Kmk.Client.get("foo")
  end

  test "list keys", c do
    :ok = c[:client] |> Kmk.Client.put("my_key", 123)
    {:ok, keys} = c[:client] |> Kmk.Client.keys
    assert Enum.any?(keys, fn {k,_v} -> k == "my_key" end)
  end

  test "last", c do
    ts = :os.system_time(:micro_seconds) / 1_000_000
    :ok = c[:client] |> Kmk.Client.put("last_value", 88)
    {:ok, {time, value}} = c[:client] |> Kmk.Client.last("last_value")
    assert value == 88
    assert_in_delta time, ts, 0.1
  end

  test "define", c do
    :ok = c[:client] |> Kmk.Client.define("foo_bar", %{type: "string"})
  end
end
