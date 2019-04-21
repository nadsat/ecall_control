defmodule Ecall.ParserTest do
  use ExUnit.Case
  alias Ecall.Control.Port

  setup do
    CallControlTest.common_setup()
  end


  test "open port, send dial, receive events", %{sim_port: uart}do
    module = Port.Sim7xxx
    {:ok, pid} = module.start_link
    cmds = for n <- module.setup_list, do: n <> "\r"
    spawn fn ->
      CallControlTest.send_async_ok(uart, cmds)
    end
    assert :ok = module.open_port(pid, CallControlTest.control_port())
    assert :ok = module.dial(pid, "272727")
    assert {:ok, "ATD272727;\r"} = Circuits.UART.read(uart)
    assert :ok = Circuits.UART.write(uart, "OK\r\n")
    Circuits.UART.drain(uart)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,2,0,0,\"272727\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:dialing, 20000)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,3,0,0,\"272727\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:ringing, 20000)
    spawn fn ->
      CallControlTest.send_async_ok(uart, ["ATA\r"])
    end
    module.answer(pid)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,0,0,0,\"272727\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:active, 20000)
    spawn fn ->
      CallControlTest.send_async_ok(uart, ["AT+CHUP\r"])
    end
    module.hang_up(pid)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,6,0,0,\"272727\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:disconnect, 20000)
  end

end
