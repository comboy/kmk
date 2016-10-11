defmodule Kmk.ClientTest do
  use ExUnit.Case

  test "ping" do
    {:ok, pid} = Kmk.Client.start_link("ws://127.0.0.1:7777")
    :pong = pid |> Kmk.Client.ping
  end
end
