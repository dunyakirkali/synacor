defmodule SynacorTest do
  use ExUnit.Case
  doctest Synacor

  test "greets the world" do
    assert Synacor.start("priv/challenge.bin") == :world
  end

  test "push when value < 32768" do
    computer = Synacor.Computer.new("priv/example.bin")
    computer = Synacor.Computer.push(computer, 12)
    assert computer.stack == [12]
  end

  test "push when value == 32768" do
    computer = Synacor.Computer.new("priv/example.bin")
    computer = update_in(computer, [:registers], &Map.put(&1, 0, 12))
    computer = Synacor.Computer.push(computer, 32768)
    assert computer.stack == [12]
  end
end
