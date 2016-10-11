defmodule Kmk.Connection do
  use GenServer
  #import Kernel, except: [send: 2]

  def start_link(ge, uri, opts, name \\ __MODULE__), do: GenServer.start_link(__MODULE__, %{ge: ge, uri: uri, opts: opts}, name: name) # safe start
  def write(data), do:  GenServer.call(__MODULE__, {:write, data})
  def write(pid, data), do:  GenServer.call(pid, {:write, data})

  # impl
  def init(%{uri: uri, opts: opts, ge: ge}) do
    %{host: host, port: port} = uri |> parse_uri 
    {:ok, socket} = Socket.Web.connect(host, port)
    Task.start_link(fn -> connection_loop(socket, ge) end)
    {:ok, %{uri: uri, opts: opts, socket: socket}}
  end

  def connection_loop(socket, ge) do
    case socket |> Socket.Web.recv! do
      {:text, reply} ->
        data = reply |> Poison.decode!
        #IO.puts "> #{data |> inspect}"
        GenEvent.notify(ge, {:received, data})
    end
    connection_loop(socket, ge)
  end

  # TODO hmm, maybe make it a cast
  def handle_call({:write, data}, _from, %{socket: socket} = state) do
    #IO.puts "< #{data |> inspect}"
    :ok = Socket.Web.send! socket, {:text, data |> Poison.encode!}
    {:reply, :ok, state}
  end

  defp parse_uri(uri) do
    # TODO default port
    parsed = ~r/ws:\/\/(?<host>.+):(?<port>\d+)/ |> Regex.named_captures(uri)
    %{
      host: parsed["host"],
      port: parsed["port"] |> String.to_integer
    }
  end
end
