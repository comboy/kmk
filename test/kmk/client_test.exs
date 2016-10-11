defmodule Kmk.ClientTest do
  use ExUnit.Case

  test "ping" do
    {:ok, pid} = Kmk.Client.start_link("ws://127.0.0.1:7777")
    :pong = pid |> Kmk.Client.ping
    100 |> :timer.sleep
  end

  test "put and get" do
    {:ok, pid} = Kmk.Client.start_link("ws://127.0.0.1:7777")
    :ok = pid |> Kmk.Client.put("foo", 123)
    {:ok, 123} = pid |> Kmk.Client.get("foo")
  end
end
