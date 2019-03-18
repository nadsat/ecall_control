defmodule Ecall.ControlTest do
  use ExUnit.Case
  alias Ecall.Control
  doctest Ecall.Control

  setup do
    CallControlTest.common_setup()
  end


  test "dial number", %{sim_port: uart}do
    {:ok, pid} = Control.start_link
    assert :ok = Control.open_device(pid, CallControlTest.control_port())
    assert :ok = Control.dial(pid, "272727")
    assert {:ok, "ATD272727;\r"} = Circuits.UART.read(uart)
    #assert_receive(:ecall_connected, 2000)
  end
end
