defmodule Disco.Command do
  @moduledoc """
  The command specification.

  A command in `Disco` is a struct which has the fields representing potential parameters
  for the command itself.

  This module defines a behaviour with a set of default callback implementations to execute
  a command on an aggregate.

  ## Define a command

  Here's how to implement a simple command without params:
  ```
  defmodule MyApp.DoSomething do
    use Disco.Command

    def run(%__MODULE__{} = _command, state) do
      [%{type: "SomethingDone", ...}]
    end
  end
  ```

  If you might need some params:
  ```
  defmodule MyApp.DoSomethingWithParams do
    use Disco.Command, foo: nil

    def run(%__MODULE__{} = command, state), do
      [%{type: "SomethingDone", ...}]
    end
  end
  ```

  It's also possible to apply validations on the params. Refer to [Vex](https://github.com/CargoSense/vex) for more details.
  ```
  defmodule MyApp.DoSomethingWithValidations do
    use Disco.Command, foo: nil, bar: nil

    # param `foo` is required, `bar` isn't.
    validates(:foo, presence: true)

    def run(%__MODULE__{} = command, state), do
      [%{type: "SomethingDone", aggregate_id: "123",...}]
    end
  end
  ```

  ## Overriding default functions

  As you can see, the simplest implementation only requires to implement `run/2` callback,
  while the others are already implemented by default. Sometimes you might need a custom
  initialization or validation function, that's why it's possible to override `new/1` and
  `validate/1`.

  ## Usage example

  _NOTE: `Disco.Factories.ExampleCommand` has been defined in `test/support/examples/example_command.ex`._

  ```
  iex> alias Disco.Factories.ExampleCommand, as: Cmd
  iex> Cmd.new(%{foo: "bar"}) == %Cmd{foo: "bar"}
  true
  iex> Cmd.new(%{foo: "bar"}) |> Cmd.validate()
  {:ok, %ExampleCommand{foo: "bar"}}
  iex> Cmd.new() |> Cmd.validate()
  {:error, %{foo: ["must be present"]}}
  iex> Cmd.run(%Cmd{foo: "bar"})
  [%{type: "FooHappened", aggregate_id: _, foo: "bar"}]
  ```
  """

  @type error :: {:error, %{atom() => [binary()]} | binary()}

  @doc """
  Called to initialize a command.
  """
  @callback new(command :: map()) :: map()

  @doc """
  Called to validate the command.
  """
  @callback validate(command :: map()) :: {:ok, map()} | error

  @doc """
  Called to run the command.
  """
  @callback run(command :: map() | error, state :: map()) :: [Disco.Event.t()] | error

  @doc """
  Called to init, validate and run the command all at once.
  """
  @callback execute(map()) :: any()

  @doc """
  Defines the struct fields and the default callbacks to implement the behaviour to run a command.

  ## Options
  The only argument accepted is a `Keyword` list of fields for the command struct.
  """
  defmacro __using__(attrs) do
    quote do
      @behaviour Disco.Command
      import Disco.Command

      defstruct unquote(attrs)

      use ExConstructor, :init
      use Vex.Struct

      @doc """
      Initializes a command.
      """
      @spec new(command :: map()) :: map()
      def new(%{} = attrs), do: init(attrs)

      @doc """
      Validates an initialized command.
      """
      @spec validate(command :: map()) :: {:ok, map()} | Disco.Command.error()
      def validate(%__MODULE__{} = command) do
        case Vex.validate(command) do
          {:ok, command} = ok -> ok
          {:error, errors} -> {:error, handle_validation_errors(errors)}
        end
      end

      @doc """
      Inits, validates and runs the command all at once.
      """
      @spec execute(attrs :: map(), state :: map()) :: any()
      def execute(attrs, %{} = state \\ %{}) do
        with %__MODULE__{} = cmd_struct <- new(attrs),
             {:ok, cmd} <- validate(cmd_struct) do
          run(cmd, state)
        else
          {:error, _errors} = error -> error
        end
      end

      defoverridable new: 1, validate: 1
    end
  end

  @doc false
  def handle_validation_errors(errors) do
    Enum.reduce(errors, %{}, fn {_, key, _, msg}, acc ->
      Map.put(acc, key, [msg])
    end)
  end

  @spec build_event(type :: binary(), payload :: map(), state :: map()) :: Disco.Event.t()
  @doc """
  Builds an event map.
  """
  def build_event(type, payload, %{id: _aggregate_id} = state) do
    Disco.Event.build(type, payload, state)
  end
end
