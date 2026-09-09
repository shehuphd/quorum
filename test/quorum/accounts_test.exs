defmodule Quorum.AccountsTest do
  use Quorum.DataCase

  alias Quorum.Accounts
  alias Quorum.Accounts.LoginToken

  describe "requesting a link" do
    test "registers a presenter the first time and reuses them after" do
      {:ok, first, _} = Accounts.request_link("a.adeyemi@university.ac.uk")
      expire_cooldown(first)
      {:ok, again, _} = Accounts.request_link("a.adeyemi@university.ac.uk")

      assert first.id == again.id
    end

    test "treats the address case-insensitively, so one person is one account" do
      {:ok, lower, _} = Accounts.request_link("a.adeyemi@university.ac.uk")
      expire_cooldown(lower)
      {:ok, upper, _} = Accounts.request_link("  A.Adeyemi@University.AC.UK  ")

      assert lower.id == upper.id
      assert upper.email == "a.adeyemi@university.ac.uk"
    end

    test "refuses something that isn't an address" do
      assert {:error, _} = Accounts.request_link("not-an-address")
      assert {:error, _} = Accounts.request_link("")
    end

    test "holds off a second link until the cooldown passes" do
      {:ok, user, _} = Accounts.request_link("a.adeyemi@university.ac.uk")

      assert {:wait, remaining} = Accounts.request_link("a.adeyemi@university.ac.uk")
      assert remaining > 0
      assert remaining <= Accounts.cooldown_seconds()
      assert Accounts.seconds_remaining(user) == remaining
    end

    test "allows another once the cooldown has passed" do
      {:ok, user, _} = Accounts.request_link("a.adeyemi@university.ac.uk")
      expire_cooldown(user)

      assert Accounts.seconds_remaining(user) == 0
      assert {:ok, _, _} = Accounts.request_link("a.adeyemi@university.ac.uk")
    end
  end

  describe "claiming a link" do
    test "signs the presenter in, once" do
      {:ok, user, token} = Accounts.request_link("a.adeyemi@university.ac.uk")

      assert {:ok, claimed} = Accounts.claim_link(token.token)
      assert claimed.id == user.id
      assert Accounts.claim_link(token.token) == :spent
    end

    test "refuses a link past its expiry, and says so" do
      {:ok, _user, token} = Accounts.request_link("a.adeyemi@university.ac.uk")

      past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      set_column(token.id, expires_at: past)

      assert Accounts.claim_link(token.token) == :expired
    end

    test "refuses a token that never existed" do
      assert Accounts.claim_link("nothing-like-a-real-token") == :invalid
    end

    test "a spent link stays spent rather than being deleted" do
      {:ok, _user, token} = Accounts.request_link("a.adeyemi@university.ac.uk")
      Accounts.claim_link(token.token)

      assert {:ok, %LoginToken{used_at: used}} = Ash.get(LoginToken, token.id)
      assert used
    end

    test "one presenter's link never signs in another" do
      {:ok, _mine, mine} = Accounts.request_link("a.adeyemi@university.ac.uk")
      {:ok, theirs_user, _} = Accounts.request_link("b.okafor@university.ac.uk")

      assert {:ok, claimed} = Accounts.claim_link(mine.token)
      refute claimed.id == theirs_user.id
    end
  end

  describe "display name" do
    test "falls back to the part before the @ until a name is set" do
      {:ok, user, _} = Accounts.request_link("a.adeyemi@university.ac.uk")
      assert Accounts.display_name(user) == "a.adeyemi"

      named = user |> Ash.Changeset.for_update(:set_name, %{name: "Dr Adeyemi"}) |> Ash.update!()
      assert Accounts.display_name(named) == "Dr Adeyemi"
    end
  end

  # Push a presenter's links back past the cooldown window. The resource has no
  # action for rewriting a timestamp, and shouldn't, so the test writes the
  # column directly rather than widening the production surface.
  defp expire_cooldown(user) do
    require Ash.Query

    LoginToken
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read!()
    |> Enum.each(
      &set_column(&1.id,
        inserted_at: DateTime.add(DateTime.utc_now(), -(Accounts.cooldown_seconds() + 5), :second)
      )
    )
  end

  defp set_column(id, fields) do
    import Ecto.Query

    Repo.update_all(from(t in "login_tokens", where: t.id == type(^id, :binary_id)), set: fields)
  end
end
