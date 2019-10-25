defmodule Project3 do
  def main(args) do
    args
    |> parse_input
    |> run
  end

  defp parse_input([numNodes, numRequests]) do
    [String.to_integer(numNodes), String.to_integer(numRequests)]
  end

  defp run([numNodes, numRequests]) do
    GenServer.start_link(Tapestry.Network, [numNodes, numRequests, self()], name: MyNetwork)
    nodes = Tapestry.start_network(numNodes)
    Tapestry.send_messages(nodes, numRequests)
    loop()
  end

  defp loop() do
    receive do
      :end -> exit(:shutdown)
    end
  end
end

Project3.main(System.argv())