defmodule Ecall.Control.Parser.Sim7xxx do
  def setup_list do
    [
      "ATE0",
      "AT+CLCC=1",
      "AT+MORING=0"
    ]
  end

  def get_event ("ok") do
    :ok
  end
end
