defmodule Ecall.Control.Port do
  require Logger
  @callback open_port(pid(), binary) :: :ok | {:error, term} 
  @callback setup(pid(), term(), term() ) :: :ok | {:error, term} 
  @callback setup_list() :: [term()] 
  @callback get_event(binary) :: term() 
  @callback start_link([term]) :: {:ok, pid} | {:error, term} 
  @callback dial(pid(), binary) :: :ok | {:error, term} 
  @callback hang_up(pid()) :: :ok 
  @callback answer(pid()) :: :ok 
  @callback reject(pid()) :: :ok 
  @callback finish(pid()) :: :ok 
  alias Ecall.Control.Port

  defmacro __using__([]) do
    quote do
      use GenStateMachine, callback_mode: :state_functions
      @behaviour Ecall.Control.Port
      defmodule StateData do
        @moduledoc false
        # from: pid of client (where the audio data is sent)
        # pid: pid of serial port process
        defstruct from: nil,
         serial_pid: nil,
         controlling_process: nil,
         cmd_list: [],
         cmd_time:  25000,
         max_time: :infinity
      end

      @impl GenStateMachine
      def init([]) do
        Logger.info "[PORT] Init Serial Port"
        case Port.init() do
          {:ok, pid} ->
              data = %StateData{serial_pid: pid}
              {:ok, :setup, data}
          err -> err
        end
      end
        
      @impl Ecall.Control.Port
      def start_link( opts \\ []) do
        GenStateMachine.start_link(__MODULE__, [], opts)
      end

      @impl Ecall.Control.Port
      def open_port(pid, name), do: Port.open_port(__MODULE__, pid, name)

      @impl Ecall.Control.Port
      def dial(pid, number), do: Port.dial(pid, number)

      @impl Ecall.Control.Port
      def hang_up(pid), do: Port.hang_up(pid)

      @impl Ecall.Control.Port
      def reject(pid), do: Port.reject(pid)

      @impl Ecall.Control.Port
      def finish(pid), do: Port.finish(pid)

      @impl Ecall.Control.Port
      def answer(pid), do: Port.answer(pid)

      @impl Ecall.Control.Port
      def setup({:call,from}, {:open, ctrl_pid, name}, data) do
         case Port.setup(data.serial_pid, name) do
           :ok ->
             cmds = __MODULE__.setup_list
             new_data = %{data | from: from,
               controlling_process: ctrl_pid,
               cmd_list: cmds}
             GenStateMachine.cast(self(), :at_cmd)
             {:next_state,:setup, new_data}
           ret ->
             {:stop, ret}
         end
      end
      @impl Ecall.Control.Port
      def setup(:cast,:at_cmd, %{cmd_list: [h|t]} = data) do
        Logger.info "[PORT][SETUP][:at_cmd]"
        new_data = %{data | cmd_list: t}
        Port.write_data(data.serial_pid,h)
        {:keep_state, new_data}
      end
      @impl Ecall.Control.Port
      def setup(:cast,:at_cmd, %{cmd_list: []} = data) do
        Logger.info "[PORT][SETUP][:at_cmd] done"
        {:next_state, :idle, data, [{:reply, data.from, :ok}]}
      end
      @impl Ecall.Control.Port
      def setup(:cast, :ok, data) do
        Logger.info "[PORT][SETUP][:ok]"
        GenStateMachine.cast(self(), :at_cmd)
        {:keep_state, data}
      end
      def setup(event_type, event_content, data) do
        handle_event(event_type, event_content, data)
      end

      def handle_event(:info, {:circuits_uart, _port, ""}, data) do
        {:keep_state, data}
      end
      def handle_event(:info, {:circuits_uart, _port, "\r"}, data) do
        {:keep_state, data}
      end
      def handle_event(:info, {:circuits_uart, _port, payload}, data) do
        Logger.info "[PORT]Data from modem arrived [#{inspect(payload)}]"
        event  = __MODULE__.get_event(payload)
        GenStateMachine.cast(self(), event)
        {:keep_state, data}
      end
      def handle_event(event_type, event_content, data) do
        Logger.info "[PORT]Data from modem arrived Generic"
        Logger.info "[PORT]TYPE #{inspect(event_type)}"
        Logger.info "[PORT]CONTENT #{inspect(event_content)}"
        pid = data.controlling_process
        send(pid, event_content)
        {:keep_state, data}
      end

      defoverridable Ecall.Control.Port
      defoverridable GenStateMachine
    end
  end

  def open_port(_module, pid, name) do
    GenStateMachine.call(pid, {:open, self(),name}, 6000)
  end

  def dial(pid, number) do
    GenStateMachine.cast(pid, {:dial, number})
  end

  def hang_up(pid) do
    GenStateMachine.cast(pid, :hang_up)
  end

  def reject(pid) do
    GenStateMachine.cast(pid, :reject)
  end

  def finish(pid) do
    GenStateMachine.cast(pid, :end_cnd)
  end

  def answer(pid) do
    GenStateMachine.cast(pid, :answer)
  end

  def init() do
    case  Circuits.UART.start_link do
      {:ok, pid} ->
        Circuits.UART.configure(pid, framing: Ecall.Framing)
        {:ok, pid}
      {:error, cause} ->
        {:stop, cause}
    end
  end

  def setup(pid, name) do
    options = [speed: 115200, active: true]
    Circuits.UART.open(pid, name, options)
  end

  def write_data(pid, data) do
    Circuits.UART.write(pid, data)
    Circuits.UART.drain(pid)
  end
end

# implementar GenStateMachine
