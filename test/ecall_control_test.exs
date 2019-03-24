defmodule Ecall.ControlTest do
  use ExUnit.Case
  alias Ecall.Control
  alias Ecall.Control.Parser
  doctest Ecall.Control

  setup do
    CallControlTest.common_setup()
  end


  test "dial number", %{sim_port: uart}do
    {:ok, pid} = Control.start_link
    cmds = for n <- Parser.Sim7xxx.setup_list, do: n <> "\r"
    spawn fn ->
      CallControlTest.send_async_ok(uart, cmds)
    end
    assert :ok = Control.open_device(pid, CallControlTest.control_port())
    assert :ok = Control.dial(pid, "272727")
    assert {:ok, "ATD272727;\r"} = Circuits.UART.read(uart)
    assert :ok = Circuits.UART.write(uart, "ok\r\n")
    Circuits.UART.drain(uart)
    #assert_receive(:ecall_connected, 2000)
  end
end
