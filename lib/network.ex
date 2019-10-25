defmodule Tapestry.Network do
  use GenServer

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init([num_nodes, num_requests, main_pid]) do
    {:ok, %{node_list: [], max_hops: 0, messages_received: 0, num_nodes: num_nodes, num_requests: num_requests, main_pid: main_pid}}
  end

  def handle_call(:get_random, from, state) do
    if Enum.empty?(state.node_list) do
      {:reply, :first_node, state}
    else
      node = state.node_list |> Enum.random()
      {:reply, node, state}
    end
  end

  def handle_cast({:message_received, hop}, state) do
    new_m = state.messages_received + 1
    IO.inspect(new_m)
    new_state = if hop > state.max_hops do
      %{state | messages_received: new_m, max_hops: hop}  
    else
      %{state | messages_received: new_m}
    end
    if new_m == state.num_requests * state.num_nodes do
      IO.inspect(state.max_hops)
      send(state.main_pid, :end)
    end
    {:noreply, new_state}
  end

  def handle_call({:add_node, node_details}, _from, state) do
    new_node_list = [node_details | state.node_list]
    new_state = %{state | node_list: new_node_list}
    {:reply, new_state, new_state}
  end
end