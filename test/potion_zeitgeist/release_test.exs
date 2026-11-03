defmodule PotionZeitgeist.ReleaseTest do
  use PotionZeitgeist.DataCase, async: true

  import PotionZeitgeist.Fixtures

  alias PotionZeitgeist.Release

  describe "vault_key_status/1" do
    test "is ok for a new installation without users" do
      assert Release.vault_key_status(Repo) == :ok
    end

    test "is ok when the stored data decrypts with the configured key" do
      user_fixture()

      assert Release.vault_key_status(Repo) == :ok
    end

    test "is a mismatch when the data was encrypted with another key" do
      user_fixture()

      {:ok, foreign} =
        Cloak.Ciphers.AES.GCM.encrypt("someone@example.com",
          tag: "AES.GCM.V1",
          key: :crypto.strong_rand_bytes(32)
        )

      Repo.query!("UPDATE users SET encrypted_email = $1", [foreign])

      assert Release.vault_key_status(Repo) == :mismatch
    end

    test "is a mismatch when the data was encrypted under another cipher tag" do
      user_fixture()

      {:ok, foreign} =
        Cloak.Ciphers.AES.GCM.encrypt("someone@example.com",
          tag: "OTHER.V1",
          key: :crypto.strong_rand_bytes(32)
        )

      Repo.query!("UPDATE users SET encrypted_email = $1", [foreign])

      assert Release.vault_key_status(Repo) == :mismatch
    end
  end
end
