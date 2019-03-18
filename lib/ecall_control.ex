defmodule Ecall.Control do
  use GenStateMachine, callback_mode: :state_functions
  require Logger
  @moduledoc """
  Make phone calls using modem with at commands.
  """
 defmodule State do
    @moduledoc false
    # from: pid of client (where the audio data is sent)
    # pid: pid of serial port process
    defstruct from: nil,
      serial_pid: nil
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
    GenStateMachine.call(pid, {:open, name})
  end

  @doc """
  Make call to a number, the call is hung up afeter max_time
  """
  @spec dial(pid(), String.t(), non_neg_integer()) :: :ok| {:error, term}
  def dial(pid, number, max_time \\ 60000) do
   GenStateMachine.cast(pid, {:dial, number, max_time}) 
  end

  #gen_state_machine callbacks
  def init([]) do
    Logger.info "Init FSM"
    case  Circuits.UART.start_link do
      {:ok, pid} ->
        Circuits.UART.configure(pid, framing: Ecall.Framing)
        state = %State{serial_pid: pid}
        #{:next_state, :idle, state}
        {:ok, :idle, state}
      {:error, cause} ->
        {:stop, cause}
    end
  end

  def idle({:call,from}, {:open,name}, data) do
    Logger.info "[IDLE][:open]"
    options = [speed: 115200, active: true]
    case Circuits.UART.open(data.serial_pid, name, options) do
      :ok -> 
        new_data = %{data | from: from}
        {:keep_state,new_data,[{:reply, from, :ok}]}
      ret -> 
        {:stop, ret}
    end
  end

  def idle(:cast, {:dial,number,_max_time}, state) do
    Logger.info "[IDLE][:dial]"
    cmd = "ATD" <> number <> ";"
    Circuits.UART.write(state.serial_pid,cmd)
    {:keep_state, state}
  end
end
