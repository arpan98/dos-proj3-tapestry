defmodule Tapestry do
  def start_network(num_nodes) do
    children = 1..num_nodes
    |> Enum.map(fn i -> 
      Supervisor.child_spec({Tapestry.Actor, [i, 4]}, id: {Tapestry.Actor, i})
    end)
    Supervisor.start_link(children, strategy: :one_for_one, name: NodeSupervisor)

    nodes = Enum.map(Supervisor.which_children(NodeSupervisor), fn child ->
      {{_, idx}, pid, _, _} = child
      id = :crypto.hash(:sha, Integer.to_string(idx)) |> Base.encode16 |> String.slice(0..3)
      {idx, id, pid}
    end)

    # Create first n-1 nodes initially with routing tables filled
    last = -1
    # Create routing tables for each node and cast them to the actor processes
    Enum.slice(nodes, 0..last) |>
    Enum.each(fn {idx, id, pid} ->
      # Routing table is a map of maps created by Enum.reduce where first key is the level and second key is the hex digit
      routing_table = Enum.reduce(0..3, %{}, fn x, acc ->
        m = Enum.reduce(0..15, %{}, fn y, acc2 -> 
          # options = All possible options for a particular spot in the table
          options = Enum.slice(nodes, 0..last) |> Enum.map(fn {nidx, nid, npid} ->
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
          {_, _, chosen_id, chosen_pid} =
            if Enum.empty?(options) do
              {"", "", "", ""}
            else
             Enum.min_by(options, fn {diff, _, _, _} -> diff end)
            end
          Map.put(acc2, Integer.to_string(y, 16), {chosen_id, chosen_pid})
        end)
        Map.put(acc, x, m)
      end)
      GenServer.call(pid, {:set_routing_table, routing_table})
      GenServer.call(MyNetwork, {:add_node, {id, pid}})
      # IO.inspect(routing_table)
    end)

    # Create last node by dynamically adding and filling routing table using acknowledged multicast
    # add_node(List.last(nodes))

    nodes
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

  def add_node({_, id, pid}) do
    new_node_details = {id, pid}
    # IO.inspect(["new node", id])
    random_node = GenServer.call(MyNetwork, :get_random)
    case random_node do
      :first_node -> GenServer.call(MyNetwork, {:add_node, new_node_details})
      {node_id, node_pid} -> 
        # IO.inspect(["random source", node_id, node_pid])
        GenServer.cast(node_pid, {:find_root_new_node, new_node_details, 0, 0})
    end
  end

end
