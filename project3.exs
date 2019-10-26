defmodule Project3 do
  def main(args) do
    args
    |> parse_input
    |> run
  end

  defp parse_input([numNodes, numRequests]) do
    [String.to_integer(numNodes), String.to_integer(numRequests), 0]
  end

  defp parse_input([numNodes, numRequests, failureProb]) do
    [String.to_integer(numNodes), String.to_integer(numRequests), String.to_float(failureProb)]
  end

  defp run([numNodes, numRequests, failureProb]) do
    GenServer.start_link(Tapestry.Network, [numNodes, numRequests, self()], name: MyNetwork)
    nodes = Tapestry.start_network(numNodes, true, self())
    # IO.inspect nodes
    # Tapestry.check_routing(nodes)

    if failureProb > 0 do
      num_failed = Tapestry.fail_nodes(nodes, failureProb)
      IO.puts("#{num_failed} failed nodes")
    end
    Tapestry.send_messages(nodes, numRequests)
    # GenServer.call(MyNetwork, :reset)
    # Tapestry.send_messages(nodes, numRequests)

    loop()
  end

  defp loop() do
    receive do
      :end -> exit(:shutdown)
    end
  end
end

Project3.main(System.argv())
