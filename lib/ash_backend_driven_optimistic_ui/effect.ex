defmodule AshBackendDrivenOptimisticUi.Effect do
  @moduledoc """
  One thing a rule does on the client: set, push or where, and in an
  `optimistic` only, insert (a create), remove, clear or edit on a list.
  """

  alias AshBackendDrivenOptimisticUi.Effect.Clear
  alias AshBackendDrivenOptimisticUi.Effect.Edit
  alias AshBackendDrivenOptimisticUi.Effect.Insert
  alias AshBackendDrivenOptimisticUi.Effect.Push
  alias AshBackendDrivenOptimisticUi.Effect.Remove
  alias AshBackendDrivenOptimisticUi.Effect.Set
  alias AshBackendDrivenOptimisticUi.Effect.Where

  @type t :: Set.t() | Push.t() | Where.t() | Insert.t() | Remove.t() | Clear.t() | Edit.t()

  @typedoc "Keys from the top of the client's record down to a nested list; a tuple step keeps only the rows matching it."
  @type nested_path :: [atom() | {atom(), keyword()}]

  @doc false
  def __entities__, do: [Set.__entity__(), Push.__entity__(), Where.__entity__()]

  @doc false
  defmacro nested_list_effect(name, describe, examples, list_doc, opts \\ []) do
    required = Keyword.get(opts, :required, true)

    from_type =
      if required,
        do: quote(do: AshBackendDrivenOptimisticUi.Effect.nested_path()),
        else: quote(do: AshBackendDrivenOptimisticUi.Effect.nested_path() | nil)

    quote do
      defstruct [:from, __spark_metadata__: nil]

      @type t :: %__MODULE__{
              from: unquote(from_type),
              __spark_metadata__: Spark.Dsl.Entity.spark_meta()
            }

      @doc false
      def __entity__ do
        %Spark.Dsl.Entity{
          name: unquote(name),
          describe: unquote(describe),
          examples: unquote(examples),
          target: __MODULE__,
          schema: [
            from: [type: {:list, :any}, required: unquote(required), doc: unquote(list_doc)]
          ]
        }
      end
    end
  end

  @doc false
  def __rule_entities__,
    do: __entities__() ++ [Insert.__entity__(), Remove.__entity__(), Clear.__entity__(), Edit.__entity__()]
end
