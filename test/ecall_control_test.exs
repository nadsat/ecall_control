defmodule Ecall.ControlTest do
  use ExUnit.Case
  doctest Ecall.Control

  test "greets the world" do
    assert Ecall.Control.hello() == :world
  end
end
