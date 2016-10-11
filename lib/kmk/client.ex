# TODO when we do a query like get the genserver is blocked, but because of query_id it doesn't have to be,
# we can use :noreply and then reply from some task
defmodule Kmk.Client do
  use GenServer
  alias Kmk.Connection

  def start_link(uri, opts \\ []), do: GenServer.start_link(__MODULE__, %{uri: uri, opts: opts})

  def init(%{uri: uri, opts: opts}) do
    import Supervisor.Spec
    worker_name = "kmk_connection_#{System.unique_integer([:positive])}" |> String.to_atom
    {:ok, ge} = GenEvent.start_link # TODO should be part of the supervision tree, we should use :name then instead of pid

    children = [ worker(Kmk.Connection, [ge, uri, opts, worker_name], restart: :permanent) ]
    # TODO we'll need some worker for subscriptions

    # TODO when server is down this restart strategy won't work for connection, we want some exponential backoff instead
    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 5)
    {:ok, %{uri: uri, opts: opts, conn: worker_name, ge: ge}}
  end

  def ping(pid), do: GenServer.call(pid, :ping)
  def put(pid, name, value), do: GenServer.call(pid, {:put, name, value})
  def get(pid, name), do: GenServer.call(pid, {:get, name})

  def handle_call(:ping, _from, state) do
    {:ok, %{"pong" => ""}} = %{ping: ""} |> query(state) |> parse_result
    {:reply, :pong, state}
  end

  def handle_call({:put, name, value}, _from, state) do
    %{put: %{key: name, value: value}}
    |> gen_reply(state)
  end

  def handle_call({:get, name}, _from, state) do
    %{get: %{key: name}} 
    |> gen_reply(state)
  end

  defp gen_reply(query, state), do: {:reply, query |> query(state) |> parse_result, state}

  defp parse_result(result) do
    case result do
      %{"result" => "ok"} -> :ok
      %{"result" => data} -> {:ok, data}
      %{"error" => error} -> {:error, error}
    end
  end

  defp query(data, %{conn: conn, ge: ge}) do
    uniq = System.unique_integer([:positive])
    task = Task.async(fn ->
      GenEvent.stream(ge)
      |> Stream.drop_while(fn (data) ->
        case data do
          {:received, %{"query_id" => ^uniq}} -> false
           _ -> true
        end
      end)
      |> Stream.take(1)
      |> Enum.to_list
      |> hd
    end)
    conn |> Connection.write(data |> Map.put(:query_id, uniq))
    {:received, reply} = task |> Task.await
    reply
  end

end
