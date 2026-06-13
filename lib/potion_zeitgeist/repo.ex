defmodule PotionZeitgeist.Repo do
  use Ecto.Repo,
    otp_app: :potion_zeitgeist,
    adapter: Ecto.Adapters.Postgres
end
