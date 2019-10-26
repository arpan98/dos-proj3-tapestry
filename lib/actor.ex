defmodule Tapestry.Actor do
  use GenServer, restart: :temporary

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init([id, num_digits]) do
    {:ok, %{routing_table: "", max_hop: num_digits, self_id: id}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:set_routing_table, routing_table}, _from, state) do
    # IO.inspect(routing_table)
    new_state = %{state | routing_table: update_routing(routing_table, state.self_id, self(), state.max_hop)} 
    {:reply, new_state, new_state}
  end

  def handle_cast({:send_to, destination, level, hop}, state) do
    {dest_id, _dest_pid} = destination
    {_next_id, next_pid, level} = next_hop(level, dest_id, false, state)
    cond do
      level == state.max_hop and state.self_id == dest_id ->
        # IO.puts("Reached #{dest_id} with #{hop} hops.")
        GenServer.cast(MyNetwork, {:message_received, hop})
      next_pid == "" -> GenServer.cast(MyNetwork, :message_failed)
      true -> GenServer.cast(next_pid, {:send_to, destination, level, hop+1})
    end
    {:noreply, state}
  end

  def handle_call({:route, new_node, level, hop}, _from, state) do
    {new_node_id, new_node_pid} = new_node
    {_next_node_id, next_node_pid, level} = next_hop(level, new_node_id, true, state)
    # IO.puts("Next Node: #{inspect({next_node_id, next_node_pid})}")
    if level == state.max_hop do
      # IO.puts("Root Node: #{inspect({state.self_id, self()})}")
      p_level = match_level(new_node_id, state) # p-level of the root node matching p-digits of new node
      # IO.inspect(["p level", new_node_id, state.self_id, p_level])
      GenServer.call(new_node_pid, {:set_routing_table, copy_p_level_routing(p_level, state)}) # Copying p-levels of root node and casting dynamic node to update its routing table
      multicast(new_node, p_level, state)
    else
      GenServer.call(next_node_pid, {:route, new_node, level, hop+1})
    end
    {:reply, state, state}
  end

  def handle_cast({:insert_new_node, node_id, node_pid}, state) do
    # IO.puts("Inserting New node #{inspect(node_id)} in #{inspect(state.self_id)} routing table")
    p_level = match_level(node_id, state)
    new_state = %{state | routing_table: update_routing(state.routing_table, node_id, node_pid, p_level)}
    {:noreply, new_state}
  end

  defp update_routing(routing, node_id, node_pid, p_level) do
    Enum.reduce(0..7, %{}, fn i_level, level_acc ->
      level_map = Enum.reduce(0..15, %{}, fn i_slot, slot_acc ->
        nodes = cond do
          i_level <= p_level and Integer.to_string(i_slot, 16) == String.at(node_id, i_level) ->
            node_list = get_node_list(routing, i_level, i_slot)
            if Enum.find(node_list, fn {nid, _} -> nid == node_id end) do
              node_list
            else
              node_list ++ [{node_id, node_pid}] # adding new node to the i-level matching slot node list
           end
          true ->
            Map.get(routing, i_level) |> Map.get(Integer.to_string(i_slot, 16))
        end
        Map.put(slot_acc, Integer.to_string(i_slot, 16), nodes)
      end)
      Map.put(level_acc, i_level, level_map)
    end)
  end

  defp get_node_list(routing, i_level, i_slot) do
    Map.get(routing, i_level)
      |> Map.get(Integer.to_string(i_slot, 16)) # nodes at i-level matching slot in the routing table of the current node
      |> Enum.filter(fn {node_id, _node_pid} -> node_id != "" end) # filtering out {"", ""} nodes current node list
  end

  defp multicast({new_node_id, new_node_pid}, p_level, state) do
    # IO.puts("Level: #{inspect(p_level)}")
    p_level_nodes = state.routing_table |> Map.get(p_level) # nodes at p-level in the routing table of the root node
    # IO.puts("p-Level Nodes: #{inspect(p_level_nodes)}")
    need_to_know_nodes = Enum.map(p_level_nodes, fn {_index, nodes} ->
        Enum.filter(nodes, fn {node_id, _node_pid} -> node_id != "" end) # filtering out {"", ""} nodes from p-level of root node list
      end)
      |> Enum.reject(fn nodes -> nodes == [] end) # rejecting [] nodes from p-level of root node list
      |> Enum.concat() # concatinating node list in each slot into one list of need-to-know nodes
    # IO.puts("Need_to_know Nodes: #{inspect(need_to_know_nodes)}")
    Enum.each(need_to_know_nodes, fn {_node_id, node_pid} ->
      GenServer.cast(node_pid, {:insert_new_node, new_node_id, new_node_pid}) # casting to all need-to-know nodes
    end)
    if p_level > 0, do: multicast({new_node_id, new_node_pid}, p_level-1, state)
  end

  defp copy_p_level_routing(p_level, state) do
    Enum.reduce(0..7,  %{}, fn i_level, level_acc ->
      cond do
        i_level <= p_level -> Map.put(level_acc, i_level, Map.get(state.routing_table, i_level)) # nodes at level not greater than p-level in the routing table of the current node
        true -> level_map = Enum.reduce(0..15, %{}, fn i_slot, slot_acc ->
          Map.put(slot_acc, Integer.to_string(i_slot, 16), [{"", ""}])
        end)
          Map.put(level_acc, i_level, level_map) # nodes at level greater than p-level in the routing table of the current node
      end
    end)
  end

  defp match_level(id, state) do
    Enum.map(0..state.max_hop-1, fn i ->
      if String.slice(state.self_id, 0..i) == String.slice(id, 0..i) do
        i+1
      else
        0
      end
    end) |> Enum.max
  end

  defp next_hop(n, g, iterate, state) do
    if n == state.max_hop do
      {state.self_id, self(), n}
    else
      d = g |> String.graphemes() |> Enum.at(n)
      {e_id, e_pid} = check_entry(state, n, d, d, 0, iterate)
      if e_id == state.self_id do
        next_hop(n+1, g, iterate, state)
      else
        {e_id, e_pid, n}
      end
    end
  end

  defp check_entry(state, n, d, d_initial, loop, iterate) do
    {e_id, e_pid} = get_entry(state, n, d)
    if loop == 1 and d == d_initial do
      {"", ""}
    else
      case {e_id, iterate} do
        {"", true} ->
          loop = 1
          new_d = d |> Integer.parse(16) |> elem(0) |> Kernel.+(1) |> rem(16) |> Integer.to_string(16)
          check_entry(state, n, new_d, d_initial, loop, iterate)
        {"", false} ->
          {"", ""}
        {e_id, _iterate} -> {e_id, e_pid}
      end
    end
  end

  defp get_entry(state, n, d, backup_idx \\ 0) do
    next = state.routing_table |> get_in([n, d])
    if backup_idx <= length(next)-1 do
      {_, next_pid} = next |> Enum.at(backup_idx)
      if next_pid != "" do
        if Process.alive?(next_pid) do
          next |> Enum.at(backup_idx)
        else
          get_entry(state, n, d, backup_idx+1)
        end
      else
        {"", ""}
      end
    else
      {"", ""}
    end
  end

end
