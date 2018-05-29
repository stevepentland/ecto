defmodule Ecto.Adapter do
  @moduledoc """
  Specifies the API required from adapters.
  """

  @type t :: module

  @typedoc "The metadata returned by the adapter init/1"
  @type adapter_meta :: term

  @typedoc "Ecto.Query metadata fields (stored in cache)"
  @type query_meta :: %{prefix: binary | nil, sources: tuple, preloads: term, select: map}

  @typedoc "Ecto.Schema metadata fields"
  @type schema_meta :: %{
          source: source,
          schema: atom,
          context: term,
          autogenerate_id: {atom, :id | :binary_id}
        }

  @type source :: {prefix :: binary | nil, table :: binary}
  @type fields :: Keyword.t()
  @type filters :: Keyword.t()
  @type constraints :: Keyword.t()
  @type returning :: [atom]
  @type prepared :: term
  @type cached :: term
  @type on_conflict ::
          {:raise, list(), []}
          | {:nothing, list(), [atom]}
          | {[atom], list(), [atom]}
          | {Ecto.Query.t(), list(), [atom]}
  @type options :: Keyword.t()

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Ensure all applications necessary to run the adapter are started.
  """
  @callback ensure_all_started(config :: Keyword.t(), type :: :application.restart_type()) ::
              {:ok, [atom]} | {:error, atom}

  @doc """
  Initializes the adapter supervision tree by returning the children and adapter metadata.
  """
  @callback init(config :: Keyword.t()) :: {:ok, :supervisor.child_spec(), adapter_meta}

  ## Types

  @doc """
  Returns the loaders for a given type.

  It receives the primitive type and the Ecto type (which may be
  primitive as well). It returns a list of loaders with the given
  type usually at the end.

  This allows developers to properly translate values coming from
  the adapters into Ecto ones. For example, if the database does not
  support booleans but instead returns 0 and 1 for them, you could
  add:

      def loaders(:boolean, type), do: [&bool_decode/1, type]
      def loaders(_primitive, type), do: [type]

      defp bool_decode(0), do: {:ok, false}
      defp bool_decode(1), do: {:ok, true}

  All adapters are required to implement a clause for `:binary_id` types,
  since they are adapter specific. If your adapter does not provide binary
  ids, you may simply use Ecto.UUID:

      def loaders(:binary_id, type), do: [Ecto.UUID, type]
      def loaders(_primitive, type), do: [type]

  """
  @callback loaders(primitive_type :: Ecto.Type.primitive(), ecto_type :: Ecto.Type.t()) ::
              [(term -> {:ok, term} | :error) | Ecto.Type.t()]

  @doc """
  Returns the dumpers for a given type.

  It receives the primitive type and the Ecto type (which may be
  primitive as well). It returns a list of dumpers with the given
  type usually at the beginning.

  This allows developers to properly translate values coming from
  the Ecto into adapter ones. For example, if the database does not
  support booleans but instead returns 0 and 1 for them, you could
  add:

      def dumpers(:boolean, type), do: [type, &bool_encode/1]
      def dumpers(_primitive, type), do: [type]

      defp bool_encode(false), do: {:ok, 0}
      defp bool_encode(true), do: {:ok, 1}

  All adapters are required to implement a clause or :binary_id types,
  since they are adapter specific. If your adapter does not provide
  binary ids, you may simply use Ecto.UUID:

      def dumpers(:binary_id, type), do: [type, Ecto.UUID]
      def dumpers(_primitive, type), do: [type]

  """
  @callback dumpers(primitive_type :: Ecto.Type.primitive(), ecto_type :: Ecto.Type.t()) ::
              [(term -> {:ok, term} | :error) | Ecto.Type.t()]

  @doc """
  Called to autogenerate a value for id/embed_id/binary_id.

  Returns the autogenerated value, or nil if it must be
  autogenerated inside the storage or raise if not supported.
  """
  @callback autogenerate(field_type :: :id | :binary_id | :embed_id) :: term | nil | no_return

  @doc """
  Commands invoked to prepare a query for `all`, `update_all` and `delete_all`.

  The returned result is given to `execute/6`.
  """
  @callback prepare(atom :: :all | :update_all | :delete_all, query :: Ecto.Query.t()) ::
              {:cache, prepared} | {:nocache, prepared}

  @doc """
  Executes a previously prepared query.

  It must return a tuple containing the number of entries and
  the result set as a list of lists. The result set may also be
  `nil` if a particular operation does not support them.

  The `meta` field is a map containing some of the fields found
  in the `Ecto.Query` struct.
  """
  @callback execute(adapter_meta, query_meta, query, params :: list(), options) :: result
            when result: {integer, [[term]] | nil} | no_return,
                 query:
                   {:nocache, prepared}
                   | {:cached, (prepared -> :ok), cached}
                   | {:cache, (cached -> :ok), prepared}

  @doc """
  Inserts multiple entries into the data store.
  """
  @callback insert_all(
              adapter_meta,
              schema_meta,
              header :: [atom],
              [fields],
              on_conflict,
              returning,
              options
            ) :: {integer, [[term]] | nil} | no_return

  @doc """
  Inserts a single new struct in the data store.

  ## Autogenerate

  The primary key will be automatically included in `returning` if the
  field has type `:id` or `:binary_id` and no value was set by the
  developer or none was autogenerated by the adapter.
  """
  @callback insert(adapter_meta, schema_meta, fields, on_conflict, returning, options) ::
              {:ok, fields} | {:invalid, constraints} | no_return

  @doc """
  Updates a single struct with the given filters.

  While `filters` can be any record column, it is expected that
  at least the primary key (or any other key that uniquely
  identifies an existing record) be given as a filter. Therefore,
  in case there is no record matching the given filters,
  `{:error, :stale}` is returned.
  """
  @callback update(adapter_meta, schema_meta, fields, filters, returning, options) ::
              {:ok, fields} | {:invalid, constraints} | {:error, :stale} | no_return

  @doc """
  Deletes a single struct with the given filters.

  While `filters` can be any record column, it is expected that
  at least the primary key (or any other key that uniquely
  identifies an existing record) be given as a filter. Therefore,
  in case there is no record matching the given filters,
  `{:error, :stale}` is returned.
  """
  @callback delete(adapter_meta, schema_meta, filters, options) ::
              {:ok, fields} | {:invalid, constraints} | {:error, :stale} | no_return

  @doc """
  Returns the adapter metadata from the `init/2` callback.

  It expects a name or a pid representing a repo.
  """
  def lookup_meta(repo_name_or_pid) do
    {_, _, meta} = Ecto.Repo.Registry.lookup(repo_name_or_pid)
    meta
  end

  @doc """
  Plans and prepares a query for the given repo, leveraging its query cache.

  This operation uses the query cache if one is available.
  """
  def prepare_query(operation, repo_name_or_pid, queryable) do
    {adapter, cache, _meta} = Ecto.Repo.Registry.lookup(repo_name_or_pid)

    {_meta, prepared, params} =
      queryable
      |> Ecto.Queryable.to_query()
      |> Ecto.Query.Planner.ensure_select(operation == :all)
      |> Ecto.Query.Planner.query(operation, cache, adapter, 0)

    {prepared, params}
  end

  @doc """
  Plans a query using the given adapter.

  This does not expect the repository and therefore does not leverage the cache.
  """
  def plan_query(operation, adapter, queryable) do
    query = Ecto.Queryable.to_query(queryable)
    {query, params, _key} = Ecto.Query.Planner.prepare(query, operation, adapter, 0)
    {query, _} = Ecto.Query.Planner.normalize(query, operation, adapter, 0)
    {query, params}
  end
end
