defmodule Tapestry do
  def start_network(num_nodes, backup_links, main_pid) do
    children = 1..num_nodes
    |> Enum.map(fn i ->
      Supervisor.child_spec({Tapestry.Actor, [i, 8]}, id: {Tapestry.Actor, i})
    end)
    Supervisor.start_link(children, strategy: :one_for_one, name: NodeSupervisor)

    all_nodes = Enum.map(Supervisor.which_children(NodeSupervisor), fn child ->
      {{_, idx}, pid, _, _} = child
      id = :crypto.hash(:sha, Integer.to_string(idx)) |> Base.encode16 |> String.slice(0..7)
      {idx, id, pid}
    end)

    [dynamic_node | active_nodes] = all_nodes
    IO.inspect active_nodes
    IO.inspect dynamic_node

    # Create first n-1 nodes initially with routing tables filled
    last = -1
    # Create routing tables for each node and cast them to the actor processes
    Enum.slice(active_nodes, 0..last) |>
    Enum.each(fn {idx, id, pid} ->
      # Routing table is a map of maps created by Enum.reduce where first key is the level and second key is the hex digit
      routing_table = Enum.reduce(0..7, %{}, fn x, acc ->
        m = Enum.reduce(0..15, %{}, fn y, acc2 ->
          # options = All possible options for a particular spot in the table
          options = Enum.slice(active_nodes, 0..last) |> Enum.map(fn {nidx, nid, npid} ->
            # IO.inspect([String.slice(id, 0..x), String.slice(nid, 0..x), String.at(nid, x+1), Integer.to_string(y, 16)])
            # Match 0..x-1 position and check (x+1)th character with the hex digit of the spot in table
            if x == 0 do
              if String.at(nid, x) == Integer.to_string(y, 16) do
                {abs(idx - nidx), nidx, nid, npid}
              end
            else
              if String.slice(id, 0..x-1) == String.slice(nid, 0..x-1) and String.at(nid, x) == Integer.to_string(y, 16) do
                {abs(idx - nidx), nidx, nid, npid}
              end
            end
          end)
          |> Enum.filter(& !is_nil(&1))
          # Choose the best option = minimum difference between indices (not hash id)
          links =
            if Enum.empty?(options) do
              [{"", ""}]
            else
             Enum.sort_by(options, fn {diff, _, _, _} -> diff end)
             |> Enum.map(fn {_, _, chosen_id, chosen_pid} -> {chosen_id, chosen_pid} end)
            end
          if backup_links do
            Map.put(acc2, Integer.to_string(y, 16), Enum.take(links, 3))
          else
            Map.put(acc2, Integer.to_string(y, 16), Enum.take(links, 1))
          end
        end)
        Map.put(acc, x, m)
      end)
      GenServer.call(pid, {:set_routing_table, routing_table})
      GenServer.call(MyNetwork, {:add_node, {id, pid}})
      # IO.inspect(routing_table)
    end)

    # Create last node by dynamically adding and filling routing table using acknowledged multicast
    insert_dynamic_node(dynamic_node, main_pid)

    active_nodes
  end

  def fail_nodes(nodes, failure_prob) do
    Enum.reduce(nodes, 0, fn {_, _, pid}, acc ->
      if fail_test(failure_prob) do
        Process.exit(pid, :kill)
        acc + 1
      else
        acc
      end
    end) # |> IO.inspect()
  end

  def send_messages(nodes, numRequests) when is_list(nodes) do
    if nodes != [] do
      [head | tail] = nodes
      {_, _, source_pid} = head
      Enum.each(1..numRequests, fn _ -> send_message(source_pid) end)
      send_messages(tail, numRequests)
    end
  end

  def send_message(source_pid) do
    destination = GenServer.call(MyNetwork, :get_random)
    GenServer.cast(source_pid, {:send_to, destination, 0, 0})
  end

  defp insert_dynamic_node({_, new_node_id, new_node_pid}, main_pid) do
    new_node = {new_node_id, new_node_pid}
    GenServer.call(new_node_pid, {:set_routing_table, init_routing()})
    {next_node_id, next_node_pid} = GenServer.call(MyNetwork, :get_random)
    IO.puts("New Node: #{inspect(new_node)}")
    IO.puts("Next Node: #{inspect({next_node_id, next_node_pid})}")
    GenServer.call(MyNetwork, {:add_node, new_node})
    GenServer.cast(next_node_pid, {:route, new_node, 0, 0})
    :timer.sleep(5000)
    GenServer.cast(next_node_pid, {:send_to, new_node, 0, 0})
    send(main_pid, :end)
  end

  defp init_routing() do
    Enum.reduce(0..7, %{}, fn i_level, level_acc ->
      level_map = Enum.reduce(0..15, %{}, fn i_slot, slot_acc ->
        Map.put(slot_acc, Integer.to_string(i_slot, 16), {"", ""})
      end)
      Map.put(level_acc, i_level, level_map)
    end)
  end

  defp fail_test(p) do
    roll = :rand.uniform()
    if roll <= p, do: true, else: false
  end

  defp check_routing(nodes) do
    Enum.each(nodes, fn { _, id, pid} ->
      IO.puts("Node: #{inspect({id, pid})} -------------------")
      GenServer.call(pid, :get_state).routing_table |> IO.inspect()
    end)
  end

end
