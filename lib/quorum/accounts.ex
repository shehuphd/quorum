defmodule Quorum.Accounts do
  @moduledoc """
  Lecturer accounts and the magic-link sign-in.

  A link is the whole credential, so the rules live here rather than in a
  controller: fifteen minutes to live, single use, and a cooldown between
  requests so the same address can't be mailed repeatedly.
  """
  use Ash.Domain, otp_app: :quorum

  require Ash.Query

  alias Quorum.Accounts.{LoginToken, User}

  resources do
    resource(Quorum.Accounts.User)
    resource(Quorum.Accounts.LoginToken)
  end

  @cooldown_seconds 30

  @doc "Seconds a lecturer waits before they can ask for another link."
  def cooldown_seconds, do: @cooldown_seconds

  @doc "Minutes a link stays valid."
  def link_ttl_minutes, do: LoginToken.ttl_minutes()

  def get_user(id), do: Ash.get(User, id)

  def get_user_by_email(email) when is_binary(email),
    do: User |> Ash.Query.filter(email == ^normalise(email)) |> Ash.read_one()

  @doc """
  Issue a sign-in link for an email address, registering the lecturer if this is
  their first one.

  Returns `{:ok, user, token}`, `{:wait, seconds}` while a recent link is still
  in its cooldown, or `{:error, changeset}` if the address doesn't look like one.
  """
  def request_link(email) do
    email = normalise(email)

    with {:ok, user} <- register(email) do
      case seconds_remaining(user) do
        0 ->
          case LoginToken
               |> Ash.Changeset.for_create(:issue, %{user_id: user.id})
               |> Ash.create() do
            {:ok, token} -> {:ok, user, token}
            error -> error
          end

        remaining ->
          {:wait, remaining}
      end
    end
  end

  @doc """
  Spend a sign-in link. Returns `{:ok, user}` once, then `:expired` for a link
  past its time and `:spent` for one already used, so the screen can say which.
  """
  def claim_link(token) when is_binary(token) do
    case LoginToken
         |> Ash.Query.filter(token == ^token)
         |> Ash.Query.load(:user)
         |> Ash.read_one() do
      {:ok, nil} ->
        :invalid

      {:ok, %LoginToken{used_at: used}} when not is_nil(used) ->
        :spent

      {:ok, %LoginToken{} = link} ->
        if DateTime.compare(DateTime.utc_now(), link.expires_at) == :gt do
          :expired
        else
          with {:ok, _} <- link |> Ash.Changeset.for_update(:spend) |> Ash.update() do
            {:ok, link.user}
          end
        end

      _ ->
        :invalid
    end
  end

  @doc "How many seconds until this lecturer may request another link. Zero when they may now."
  def seconds_remaining(%User{} = user) do
    case last_issued_at(user) do
      nil ->
        0

      at ->
        elapsed = DateTime.diff(DateTime.utc_now(), at, :second)
        if elapsed >= @cooldown_seconds, do: 0, else: @cooldown_seconds - elapsed
    end
  end

  @doc "What to call a lecturer on screen before they've set a name."
  def display_name(%User{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%User{email: email}), do: email |> String.split("@") |> hd()

  defp register(email),
    do: User |> Ash.Changeset.for_create(:register, %{email: email}) |> Ash.create()

  defp last_issued_at(user) do
    LoginToken
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one()
    |> case do
      {:ok, %LoginToken{inserted_at: at}} -> at
      _ -> nil
    end
  end

  defp normalise(email), do: email |> to_string() |> String.trim() |> String.downcase()
end
