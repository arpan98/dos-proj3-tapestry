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
    GenServer.start_link(Tapestry.Network, [numRequests, self()], name: MyNetwork)
    Tapestry.create_network(numNodes)
    # Enum.each(1..numRequests, fn _ -> Tapestry.send_message() end)
    loop()
  end

  defp loop() do
    receive do
      :end -> exit(:shutdown)
    end
  end
end

Project3.main(System.argv())