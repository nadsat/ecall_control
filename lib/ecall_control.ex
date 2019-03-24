defmodule Ecall.Control do
  use GenStateMachine, callback_mode: :state_functions
  require Logger
  alias Ecall.Control.Parser
  @moduledoc """
  Make phone calls using modem with at commands.
  """
 defmodule StateData do
    @moduledoc false
    # from: pid of client (where the audio data is sent)
    # pid: pid of serial port process
    defstruct from: nil,
      serial_pid: nil,
      cmd_list: []
  end

  @doc """
  Start up a CallControl GenStateMachine.
  """
  @spec start_link( [term]) :: {:ok, pid} | {:error, term}
  def start_link( opts \\ []) do
    GenStateMachine.start_link(__MODULE__, [], opts)
  end

  @doc """
  open a serial device to send and receive AT commands
  """
  @spec open_device(pid(), binary) :: :ok | {:error, term}
  def open_device(pid, name) do
    GenStateMachine.call(pid, {:open, name}, 6000)
  end

  @doc """
  Make call to a number, the call is hung up afeter max_time
  """
  @spec dial(pid(), String.t(), non_neg_integer()) :: :ok| {:error, term}
  def dial(pid, number, max_time \\ 5000) do
   GenStateMachine.cast(pid, {:dial, number, max_time}) 
  end

  #gen_state_machine callbacks
  def init([]) do
    Logger.info "Init FSM"
    case  Circuits.UART.start_link do
      {:ok, pid} ->
        Circuits.UART.configure(pid, framing: Ecall.Framing)
        data = %StateData{serial_pid: pid}
        #{:next_state, :idle, state}
        {:ok, :setup, data}
      {:error, cause} ->
        {:stop, cause}
    end
  end

  def setup({:call,from}, {:open,name}, data) do
    Logger.info "[SETUP][:open]"
    options = [speed: 115200, active: true]
    case Circuits.UART.open(data.serial_pid, name, options) do
      :ok -> 
        cmds = Parser.Sim7xxx.setup_list
        new_data = %{data | from: from, cmd_list: cmds}
        #{:keep_state,new_data,[{:reply, from, :ok}]}
        GenStateMachine.cast(self(), :at_cmd)
        {:next_state,:setup, new_data}
      ret -> 
        {:stop, ret}
    end
  end

  def setup(:cast,:at_cmd, %{cmd_list: [h|t]} = data) do
    Logger.info "[SETUP][:at_cmd]"
    new_data = %{data | cmd_list: t}
    Circuits.UART.write(data.serial_pid,h)
    Circuits.UART.drain(data.serial_pid)
    {:keep_state, new_data}
  end

  def setup(:cast,:at_cmd, %{cmd_list: []} = data) do
    Logger.info "[SETUP][:at_cmd] done"
    {:next_state, :idle, data, [{:reply, data.from, :ok}]}
  end
  def setup(:cast, :ok, data) do
    Logger.info "[SETUP][:ok]"
    GenStateMachine.cast(self(), :at_cmd)
    {:keep_state, data}
  end

  def setup(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def idle(:cast, {:dial,number,_max_time}, data) do
    Logger.info "[IDLE][:dial]"
    cmd = "ATD" <> number <> ";"
    Circuits.UART.write(data.serial_pid,cmd)
    {:keep_state, data}
  end

  def idle(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def handle_event(:info, {:circuits_uart, _port, payload}, data) do
    Logger.info "Data from modem arrived [#{inspect(payload)}]"
    event  = Parser.Sim7xxx.get_event(payload)
    GenStateMachine.cast(self(), event)
    {:keep_state, data}
  end
  def handle_event(event_type, event_content, data) do
    Logger.info "Data from modem arrived Generic"
    Logger.info event_type
    Logger.info event_content
    Logger.info data
    {:keep_state_and_data}
  end
end
