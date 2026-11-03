defmodule PotionZeitgeist.Release do
  @moduledoc """
  Tasks for a compiled release, where Mix is not available.

  The Docker image runs `setup/0` on every start (see `docker-entrypoint.sh`).
  `migrate/0` and `rollback/2` can be run by hand:

      bin/potion_zeitgeist eval "PotionZeitgeist.Release.migrate()"
  """

  @app :potion_zeitgeist

  @doc """
  Prepares the database before the server starts.

  Waits until the database accepts connections, stops with a clear message
  when `VAULT_KEY` cannot decrypt the data already stored (instead of starting
  an app that cannot read its own data), then runs pending migrations.
  Migrations only add to the schema; they never reset existing data.
  """
  def setup do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          wait_for_database!(repo)
          start_vault!()

          if vault_key_status(repo) == :mismatch do
            IO.puts(:stderr, vault_key_mismatch_message())
            System.halt(1)
          end

          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end

    :ok
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Tells whether the configured vault key can read the stored personal data.

  Returns `:ok` when a stored e-mail address decrypts with the current key or
  when nothing is stored yet (new installation), and `:mismatch` when none of
  the stored values decrypts, i.e. they were encrypted with another key.
  Needs a started `PotionZeitgeist.Vault`.
  """
  def vault_key_status(repo) do
    if table_exists?(repo, "users") do
      %{rows: rows} =
        repo.query!("SELECT encrypted_email FROM users ORDER BY id LIMIT 5", [], log: false)

      cond do
        rows == [] -> :ok
        Enum.any?(rows, fn [ciphertext] -> decrypts?(ciphertext) end) -> :ok
        true -> :mismatch
      end
    else
      :ok
    end
  end

  defp table_exists?(repo, table) do
    %{rows: [[exists?]]} =
      repo.query!("SELECT to_regclass($1) IS NOT NULL", ["public." <> table], log: false)

    exists?
  end

  # A wrong key makes AES-GCM return :error as the "plaintext"; a value
  # encrypted under another cipher tag gives {:error, _}.
  defp decrypts?(ciphertext) when is_binary(ciphertext) do
    match?({:ok, plaintext} when is_binary(plaintext), PotionZeitgeist.Vault.decrypt(ciphertext))
  rescue
    _ -> false
  end

  defp decrypts?(_ciphertext), do: false

  defp start_vault! do
    {:ok, _} = Application.ensure_all_started(:crypto)

    case PotionZeitgeist.Vault.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  # After a host reboot Docker starts the app and the database at the same
  # time, so the database may need a few seconds before it accepts connections.
  defp wait_for_database!(repo, attempts_left \\ 30) do
    repo.query!("SELECT 1", [], log: false)
    :ok
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      if attempts_left > 1 do
        IO.puts("Waiting for the database: #{Exception.message(error)}")
        Process.sleep(2_000)
        wait_for_database!(repo, attempts_left - 1)
      else
        IO.puts(:stderr, """
        The database could not be reached. Check that the database container
        runs and that DATABASE_URL (user, password, host, database) is right.
        Note: POSTGRES_PASSWORD only takes effect when the database volume is
        created for the first time; changing it later does not change the
        password of an existing database.
        """)

        reraise error, __STACKTRACE__
      end
  end

  defp vault_key_mismatch_message do
    """

    ==========================================================================
    VAULT_KEY does not match the data in the database.

    The names and e-mail addresses in the database were encrypted with a
    different key. With this key the app could not read them, so it does not
    start. Your data has not been changed.

    Put the original key back, then start the app again:
      * Docker: restore secrets.env into the app data volume
        (/app/data/secrets.env) from your backup, or set VAULT_KEY in .env to
        the key the data was created with.
      * Without Docker: set the VAULT_KEY environment variable to that key.
    ==========================================================================
    """
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.load(@app)
end
