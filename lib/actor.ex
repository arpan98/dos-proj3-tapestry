defmodule Tapestry.Actor do
  use GenServer

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init([idx, num_digits]) do
    self_id = :crypto.hash(:sha, Integer.to_string(idx)) |> Base.encode16 |> String.slice(0..num_digits-1)
    {:ok, %{routing_table: "", max_hop: num_digits, self_id: self_id}}
  end

  def handle_call({:set_routing_table, routing_table}, _from, state) do
    # IO.inspect(routing_table)
    new_state = Map.put(state, :routing_table, routing_table)
    {:reply, new_state, new_state}
  end

  def handle_cast({:send_to, destination, level, hop}, state) do
    {dest_id, _} = destination
    {next_id, next_pid, level} = next_hop(level, dest_id, state)
    if level == state.max_hop and state.self_id == dest_id do
      IO.puts("Reached #{dest_id} with #{hop} hops.")
      GenServer.cast(MyNetwork, {:message_received, hop})
    else
      GenServer.cast(next_pid, {:send_to, destination, level, hop+1})
    end
    {:noreply, state}
  end  

  def handle_cast({:find_root_new_node, new_node_details, level, hop}, state) do
    if level == state.max_hop do
      # IO.inspect(["found root", state.self_id, hop, level])
      acknowledged_multicast(new_node_details, state)
    else
      # IO.inspect(["new node", new_node_details])
      {new_id, new_pid} = new_node_details
      {next_id, next_pid, level} = next_hop(level, new_id, state)
      # IO.inspect(["next hop", {next_id, next_pid, level}])
      GenServer.cast(next_pid, {:find_root_new_node, new_node_details, level, hop+1})
    end
    {:noreply, state}
  end

  def acknowledged_multicast(new_node_details, state) do
    {new_id, _} = new_node_details
    p = Enum.map(0..state.max_hop-1, fn i ->
      if String.slice(state.self_id, 0..i) == String.slice(new_id, 0..i) do
        i+1
      else
        0
      end
    end) |> Enum.max
    IO.inspect([state.self_id, new_id, p])
    
    # Enum.each(0..15, fn i ->
    #   {id, pid} = get_in(state.routing_table, [p, i])
    #   GenServer.cast({:acknowledged_multicast, })
    # end)
  end

  def next_hop(n, g, state) do
    if n == state.max_hop do
      {state.self_id, self(), n}
    else
      d = g |> String.graphemes() |> Enum.at(n)
      {e_id, e_pid} = check_entry(state, n, d, d, 0)
      if e_id == state.self_id do
        next_hop(n+1, g, state)
      else
        {e_id, e_pid, n}
      end
    end
  end

  def check_entry(state, n, d, d_initial, loop) do
    {e_id, e_pid} = get_in(state.routing_table, [n, d])
    if loop == 1 and d == d_initial do
      {state.self_id, self()}
    else
      if e_id == "" do
        loop = 1
        new_d = d |> Integer.parse(16) |> elem(0) |> Kernel.+(1) |> rem(16) |> Integer.to_string(16)
        check_entry(state, n, new_d, d_initial, loop)
      else
        {e_id, e_pid}
      end
    end
  end
end