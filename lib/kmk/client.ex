# TODO when we do a query like get the genserver is blocked, but because of query_id it doesn't have to be,
# we can use :noreply and then reply from some task
# TODO currently whene there's no connection there will be timeouts or errors, it would be nice to have a blocking mode
# which blocks put/get until connection is reestablished
defmodule Kmk.Client do
  use GenServer
  alias Kmk.Connection

  def start_link(uri, opts \\ []), do: GenServer.start_link(__MODULE__, %{uri: uri, opts: opts})

  def init(%{uri: uri, opts: opts}) do
    import Supervisor.Spec
    worker_name = "kmk_connection_#{System.unique_integer([:positive])}" |> String.to_atom
    {:ok, ge} = GenEvent.start_link # TODO should be part of the supervision tree, we should use :name then instead of pid

    client = self
    Task.start_link(fn -> subscriptions_handler(client, ge) end) # TODO supervise, no need to crash the client

    children = [ worker(Kmk.Connection, [ge, uri, opts, worker_name], restart: :permanent) ]
    # TODO we'll need some worker for subscriptions


    # TODO when server is down this restart strategy won't work for connection, we want some exponential backoff instead
    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 5)
    {:ok, %{
        uri: uri,
        opts: opts,
        subscriptions: %{},
        conn: worker_name, # Kmk.Connection
        ge: ge # GenEvent
      }}
  end

  def subscriptions_handler(client, ge) do
    GenEvent.stream(ge)
    |> Stream.filter(fn {:received, data} -> data["pub"] end)
    |> Stream.each(fn {:received, %{"pub" => pub}} ->
      # symbolize keys
      pub = pub |> Enum.map(fn {k,v} -> {k |> String.to_atom, v} end) |> Enum.into(%{})
      send(client, {:pub, pub})
    end)
    |> Enum.take(1) # This feels wrong, maybe just go with use GenEvent and then handle_event
    subscriptions_handler(client, ge)
  end

  def ping(pid), do: GenServer.call(pid, :ping)
  def put(pid, name, value), do: GenServer.call(pid, {:put, name, value})
  def get(pid, name), do: GenServer.call(pid, {:get, name})
  def last(pid, name), do: GenServer.call(pid, {:last, name})
  def define(pid, name, opts), do: GenServer.call(pid, {:define, name, opts})
  def keys(pid, opts \\ %{}), do: GenServer.call(pid, {:keys, opts})
  def subscribe(pid, name), do: GenServer.call(pid, {:subscribe, name})
  def unsubscribe(pid, name), do: GenServer.call(pid, {:unsubscribe, name})

  def handle_call(:ping, _from, state) do
    {:ok, %{"pong" => ""}} = %{ping: ""} |> query(state) |> parse_result
    {:reply, :pong, state}
  end

  # TODO async mode, maybe make it a cast, + some logging 
  def handle_call({:put, name, value}, _from, state) do
    %{put: %{key: name, value: value}}
    |> gen_reply(state)
  end

  def handle_call({:get, name}, _from, state) do
    %{get: %{key: name}}
    |> gen_reply(state)
  end

  def handle_call({:last, name}, _from, state) do
    reply = %{last: %{key: name}}
      |> query(state)
      |> refine_result(fn (result) ->
        {result["time"], result["value"]}
      end)
    {:reply, reply, state}
  end

  def handle_call({:define, name, opts}, _from, state) do
    %{define: %{name => opts}}
    |> gen_reply(state)
  end

  def handle_call({:keys, opts}, _from, state) do
    %{keys: opts}
    |> gen_reply(state)
  end

  # TODO ignore double subscribe
  # TODO replay subscriptions on reconnect, that's why we store them
  def handle_call({:subscribe, name}, {pid, _ref}, state) do
    case %{sub: %{key: name}} |> query(state) |> parse_result do
      :ok ->
        subs = state[:subscriptions][name] || []
        state = state |> Map.put(:subscriptions, state[:subscriptions] |> Map.put(name, subs ++ [pid]))
        {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:unsubscribe, name}, {pid, _ref}, state) do
    case %{unsub: %{key: name}} |> query(state) |> parse_result do
      :ok ->
        subs = state[:subscriptions][name] || []
        state = state |> Map.put(:subscriptions, state[:subscriptions] |> Enum.filter(fn pid_ -> pid_ != pid end))
        {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  def handle_info({:pub, pub}, state) do
    (state[:subscriptions][pub[:key]] || []) |> Enum.each(fn pid ->
      send(pid, {:pub, pub})
    end)
    {:noreply, state}
  end

  defp gen_reply(query, state), do: {:reply, query |> query(state) |> parse_result, state}

  defp parse_result(result) do
    case result do
      %{"result" => "ok"} -> :ok
      %{"result" => data} -> {:ok, data}
      %{"error" => error} -> {:error, error}
    end
  end

  defp refine_result(result, fun) do
    case result |> parse_result do
      {:error, error} -> {:error, error}
      {:ok, data} -> {:ok, fun.(data)}
    end
  end

  defp query(data, %{conn: conn, ge: ge}) do
    uniq = System.unique_integer([:positive])
    task = Task.async(fn ->
      GenEvent.stream(ge)
      |> Stream.filter(fn {:received, data} -> data["query_id"] == uniq end)
      |> Stream.take(1)
      |> Enum.to_list
      |> hd
    end)
    conn |> Connection.write(data |> Map.put(:query_id, uniq))
    {:received, reply} = task |> Task.await
    reply
  end

end
