defmodule Tapestry.Network do
  use GenServer

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init([num_nodes, num_requests, main_pid]) do
    {:ok, %{node_list: [], max_hops: 0, total_messages: 0, messages_received: 0, num_nodes: num_nodes, num_requests: num_requests, main_pid: main_pid}}
  end

  def handle_call(:get_random, _from, state) do
    if Enum.empty?(state.node_list) do
      {:reply, :first_node, state}
    else
      node = state.node_list |> Enum.random()
      {:reply, node, state}
    end
  end

  def handle_cast({:message_received, hop}, state) do
    new_m = state.messages_received + 1
    new_total = state.total_messages + 1
    new_state = if hop > state.max_hops do
      %{state | messages_received: new_m, total_messages: new_total, max_hops: hop}
    else
      %{state | messages_received: new_m, total_messages: new_total}
    end
    if new_total == state.num_requests * state.num_nodes do
      IO.puts("Max hops = #{state.max_hops}")
      IO.puts("Successfully delivered #{state.messages_received+1} out of #{state.total_messages+1} requests.")
      send(state.main_pid, :end)
    end
    {:noreply, new_state}
  end

  def handle_cast(:message_failed, state) do
    new_total = state.total_messages + 1
    new_state = %{state | total_messages: new_total}
    if new_total == state.num_requests * state.num_nodes do
      IO.puts("Max hops = #{state.max_hops}")
      IO.puts("Successfully delivered #{state.messages_received+1} out of #{state.total_messages+1} requests.")
      send(state.main_pid, :end)
    end
    {:noreply, new_state}
  end

  def handle_call({:add_node, node_details}, _from, state) do
    new_node_list = [node_details | state.node_list]
    new_state = %{state | node_list: new_node_list}
    {:reply, new_state, new_state}
  end

  def handle_call({:remove_node, node_details}, _from, state) do
    new_node_list = List.delete(state.node_list, node_details)
    new_num_nodes = state.num_nodes - 1
    new_state = %{state | num_nodes: new_num_nodes, node_list: new_node_list}
    {:reply, new_state, new_state}
  end

  def handle_call(:reset, _from, state) do
    new_state = %{state | node_list: [], max_hops: 0, messages_received: 0}
    {:reply, new_state, new_state}
  end

  def handle_call(:get_nodes, _from, state) do
    {:reply, state.node_list, state}
  end

end
