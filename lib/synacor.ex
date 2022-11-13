defmodule Synacor do
  alias __MODULE__.Computer

  use Bitwise

  def start(filename) do
    %{state: :halted} = run(Computer.new(filename))
  end

  defp run(computer, inputs \\ []) do
    Computer.run(computer, inputs)
    #    {output, computer} = Computer.pop_outputs(computer)
    #    IO.puts([output, ?\n])
    #    with %{state: :awaiting_input} <- computer, do: run(computer, String.to_charlist(IO.gets("? ")))
  end

  defmodule Computer do
    @max 32768

    def new(filename) do
      %{
        state: :ready,
        stack: [],
        ip: 0,
        memory: initial_memory(filename),
        registers: initial_registers()
      }
    end

    def run(%{state: state} = computer, _inputs \\ []) when state in [:ready, :awaiting_input] do
      computer
      #      |> push_inputs(inputs)
      |> Stream.iterate(&execute_instruction/1)
      |> Enum.find(&(&1.state != :ready))
    end

    defp initial_registers() do
      for r <- 0..7, into: %{}, do: {r, 0}
    end

    defp initial_memory(filename) do
      for <<number::size(16)-unsigned-integer-little <- File.read!(filename)>> do
        number
      end
      |> Stream.with_index()
      |> Stream.map(fn {value, index} -> {index, value} end)
      |> Map.new()
    end

    defp execute_instruction(%{ip: ip} = computer) do
#      ip |> IO.inspect(label: "ip")
      code = mem_read(computer, ip)
#       |> IO.inspect(label: "code")
      {fun, arity} = fun_info(code)
      params = parameters(computer, code, arity)
#      |> IO.inspect(label: "params")
      with %{state: :ready, ip: ^ip} = computer <- apply(fun, [computer | params]) do
        update_in(computer.ip, &(&1 + arity + 1))
      end
    end

    defp fun_info(code) do
      fun = Map.fetch!(instruction_table(), code)
#      |> IO.inspect
      {:arity, arity} = Function.info(fun, :arity)
      {fun, arity - 1}
    end

    defp parameters(computer, code, arity) do
      Stream.unfold(
        {1, code},
        fn {offset, mode_acc} ->
          value = mem_read(computer, computer.ip + offset)
          {value, {offset + 1, mode_acc}}
        end
      )
      |> Enum.take(arity)

      #      |> IO.inspect(label: "params")
    end

    defp value(computer, a) when a < @max, do: a
    defp value(computer, a), do: reg_read(computer, a - @max)

    defp write(computer, a, res) when a < @max, do: update_in(computer, [:memory], &Map.put(&1, a, res))
    defp write(computer, a, res), do: update_in(computer, [:registers], &Map.put(&1, a - @max, res))

    defp mem_read(computer, address) when address >= 0, do: Map.get(computer.memory, address, 0)
    defp reg_read(computer, address), do: Map.get(computer.registers, address, 0)

    defp instruction_table() do
      %{
        0 => &halt/1,
        1 => &set/3,
        2 => &push/2,
        3 => &pop/2,
        4 => &eq/4,
        5 => &gt/4,
        6 => &jmp/2,
        7 => &jt/3,
        8 => &jf/3,
        9 => &add/4,
        10 => &mult/4,
        11 => &mod/4,
        12 => &andd/4,
        13 => &orr/4,
        14 => &nott/3,
        15 => &rmem/3,
        16 => &wmem/3,
        17 => &call/2,
        18 => &ret/1,
        19 => &out/2,
#        20 => &in/3,
        21 => &noop/1
      }
    end

    defp halt(computer) do
      %{computer | state: :halted}
    end

    defp set(computer, a, b) do
      update_in(computer, [:registers], &Map.put(&1, a - @max, value(computer, b)))
    end

    def push(computer, a) do
      update_in(computer, [:stack], &[value(computer, a) | &1])
    end

    defp pop(computer, a) do
      [res | t] = computer.stack

      computer
      |> write(a, res)
      |> Map.put(:stack, t)
    end

    defp eq(computer, a, b, c) do
      res = if value(computer, b) == value(computer, c), do: 1, else: 0
      write(computer, a, res)
    end

    defp gt(computer, a, b, c) do
      res = if value(computer, b) > value(computer, c), do: 1, else: 0
      write(computer, a, res)
    end

    defp jmp(computer, a) do
      %{computer | ip: value(computer, a)}
    end

    defp jt(computer, a, b) do
      if value(computer, a) != 0 do
        %{computer | ip: value(computer, b)}
      else
        computer
      end
    end

    defp jf(computer, a, b) do
      if value(computer, a) == 0 do
        %{computer | ip: value(computer, b)}
      else
        computer
      end
    end

    defp add(computer, a, b, c) do
      res = rem(value(computer, b) + value(computer, c), @max)
      write(computer, a, res)
    end

    defp mult(computer, a, b, c) do
      res = rem(value(computer, b) * value(computer, c), @max)
      write(computer, a, res)
    end

    defp mod(computer, a, b, c) do
      res = rem(value(computer, b), value(computer, c))
      write(computer, a, res)
    end

    defp andd(computer, a, b, c) do
      res = value(computer, b) &&& value(computer, c)
      write(computer, a, res)
    end

    defp orr(computer, a, b, c) do
      res = value(computer, b) ||| value(computer, c)
      write(computer, a, res)
    end

    defp nott(computer, a, b) do
      << _::1, res::15 >> = <<Bitwise.bnot(b)::16 >>
      write(computer, a, res)
    end

    defp rmem(computer, a, b) do
      res = mem_read(computer, value(computer, b))
      write(computer, a, res)
    end

    defp wmem(computer, a, b) do
      write(computer, value(computer, a), value(computer, b))
    end

    defp call(computer, a) do
      computer
      |> push(computer.ip + 2)
      |> jmp(value(computer, a))
    end

    defp ret(computer) do
      [res | t] = computer.stack

      computer
      |> Map.put(:stack, t)
      |> jmp(res)
    end

    defp out(computer, param) do
      IO.write([param])
      computer
    end

    defp noop(computer), do: computer
  end
end
