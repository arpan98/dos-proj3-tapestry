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
		sha1 = :crypto.hash(:sha, "#{numNodes}") |> Base.encode16
		sha2 = :crypto.hash(:sha, "#{numRequests}") |> Base.encode16
		# IO.puts("#{sha1} #{sha2}")
		IO.inspect(sha1)
		IO.inspect(sha2)
	end
end

Project3.main(System.argv())