defmodule Kmk.Client do
  use GenServer
  alias Kmk.Connection

  def start_link(uri, opts \\ []), do: GenServer.start_link(__MODULE__, %{uri: uri, opts: opts})

  def init(%{uri: uri, opts: opts}) do
    import Supervisor.Spec
    worker_name = "kmk_connection_#{System.unique_integer([:positive])}" |> String.to_atom
    {:ok, pid} = GenEvent.start_link

    children = [ worker(Kmk.Connection, [self, uri, opts, worker_name], restart: :permanent) ]
    # TODO we'll need some worker for subscriptions

    # TODO when server is down this restart strategy won't work for connection, we want some exponential backoff instead
    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 5)
    {:ok, %{uri: uri, opts: opts, conn: worker_name, ge: pid}}
  end

  def ping(pid), do: GenServer.call(pid, :ping)

  def handle_call(:ping, _from, %{conn: conn, ge: ge} = state) do
    uniq = System.unique_integer([:positive])
    task = Task.async(fn ->
      GenEvent.stream(ge) 
      |> Stream.drop_while(fn (data) -> 
        case data do
          {:received, %{"result" => %{"pong" => ^uniq}}} -> false
           _ -> true
        end
      end)
      |> Stream.take(1)
    end)
    conn |> Connection.write(%{ping: uniq})
    task |> Task.await
    {:reply, :pong, state}
  end

  def handle_info({:received, data}, %{ge: ge} = state) do
    GenEvent.notify(ge, {:received, data})
    {:noreply, state}
  end

end
