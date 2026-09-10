# Stands in for a mailer with nothing behind it: Swoosh's local adapter calls a
# process that some environments never start, and a GenServer call to a missing
# process exits rather than returning an error.
defmodule QuorumTest.DeadMailer do
  @behaviour Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: exit({:noproc, {GenServer, :call, [:nowhere, :push, 5000]}})

  @impl true
  def validate_config(_config), do: :ok
end

defmodule QuorumWeb.StandingPagesTest do
  use QuorumWeb.ConnCase

  import Swoosh.TestAssertions

  alias Quorum.Contact
  alias Quorum.Contact.Limit

  @valid %{
    "name" => "Ada Lovelace",
    "email" => "ada@example.ac.uk",
    "message" => "Does Quorum work on eduroam?"
  }

  describe "the footer's three pages" do
    test "every page the footer links to exists", %{conn: conn} do
      for path <- ["/privacy", "/accessibility", "/contact"] do
        assert conn |> get(path) |> html_response(200)
      end
    end

    test "the footer links to all three from the landing page", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(href="/privacy")
      assert html =~ ~s(href="/accessibility")
      assert html =~ ~s(href="/contact")
    end

    test "privacy says what is stored and marks itself a draft", %{conn: conn} do
      html = conn |> get(~p"/privacy") |> html_response(200)

      assert html =~ "This is a working draft."
      assert html =~ "no name, no email, and no account"
      assert html =~ "_quorum_key"
      assert html =~ "no analytics cookies"
    end

    test "accessibility states the target and owns its gaps", %{conn: conn} do
      html = conn |> get(~p"/accessibility") |> html_response(200)

      assert html =~ "WCAG 2.2 AA"
      assert html =~ "Known gaps"
      assert html =~ "No independent audit has been done."
      assert html =~ "Report an accessibility problem"
    end
  end

  describe "the contact form" do
    # The server-side wait outlives a request, so each test starts from nothing.
    setup do
      Quorum.Contact.Limit.reset()
      :ok
    end

    test "renders a labelled field for every input", %{conn: conn} do
      html = conn |> get(~p"/contact") |> html_response(200)

      for field <- ~w(name email message) do
        assert html =~ ~s(for="#{field}")
        assert html =~ ~s(id="#{field}")
      end
    end

    test "a valid message reaches the contact address, with the sender on reply-to", %{conn: conn} do
      html = conn |> post(~p"/contact", @valid) |> html_response(200)

      assert html =~ "Message sent."

      assert_email_sent(fn email ->
        assert email.to == [{"", Contact.recipient()}]
        assert email.reply_to == {"Ada Lovelace", "ada@example.ac.uk"}
        assert email.subject == "Quorum contact from Ada Lovelace"
        assert email.text_body =~ "Does Quorum work on eduroam?"
      end)
    end

    test "a mailer that can't send says so, and keeps what was typed", %{conn: conn} do
      # The local adapter's storage isn't started in every environment, and a
      # provider can be unreachable. Either exits rather than returning an
      # error, which used to take the whole request down with it.
      original = Application.get_env(:quorum, Quorum.Mailer)
      Application.put_env(:quorum, Quorum.Mailer, adapter: QuorumTest.DeadMailer)
      on_exit(fn -> Application.put_env(:quorum, Quorum.Mailer, original) end)

      html = conn |> post(~p"/contact", @valid) |> html_response(200)

      assert html =~ "That didn&#39;t send"
      refute html =~ "Message sent."
      assert html =~ "Does Quorum work on eduroam?"
    end

    test "a sent message leaves the form in place and empty", %{conn: conn} do
      html = conn |> post(~p"/contact", @valid) |> html_response(200)

      assert html =~ "Message sent."
      refute html =~ "Back to the start"

      # The form is still there to send another, carrying none of the last one.
      assert html =~ ~s(action="/contact")
      assert html =~ "Send message"

      assert html =~
               ~s(<input id="name" name="name" class="q-input" maxlength="120" required autocomplete="name" value="">)

      refute html =~ "Ada Lovelace"
      refute html =~ "Does Quorum work on eduroam?"
    end

    test "the sender's address is never forged as the from address", %{conn: conn} do
      post(conn, ~p"/contact", @valid)

      assert_email_sent(fn email ->
        assert {_, "no-reply@quorum.app"} = email.from
      end)
    end

    test "each missing field is reported beside itself, and nothing is sent", %{conn: conn} do
      html =
        conn
        |> post(~p"/contact", %{"name" => "", "email" => "", "message" => ""})
        |> html_response(422)

      assert html =~ "Tell us who you are."
      assert html =~ "We need an address to reply to."
      assert html =~ "Write your message first."
      assert_no_email_sent()
    end

    test "a bad address is refused and the message is kept for the retry", %{conn: conn} do
      html =
        conn
        |> post(~p"/contact", %{@valid | "email" => "not-an-address"})
        |> html_response(422)

      assert html =~ "That doesn&#39;t look like an email address."
      assert html =~ "Does Quorum work on eduroam?"
      assert_no_email_sent()
    end

    test "an over-long message is refused", %{conn: conn} do
      conn
      |> post(~p"/contact", %{@valid | "message" => String.duplicate("a", 4001)})
      |> html_response(422)

      assert_no_email_sent()
    end

    test "a filled honeypot sends nothing and tells the bot nothing", %{conn: conn} do
      html =
        conn
        |> post(~p"/contact", Map.put(@valid, "website", "http://spam.example"))
        |> html_response(200)

      # Reads as success, so a bot learns nothing from the response.
      assert html =~ "Message sent."
      assert_no_email_sent()
    end

    test "a second message straight away is held off", %{conn: conn} do
      conn = post(conn, ~p"/contact", @valid)
      assert_email_sent()

      html =
        conn
        |> recycle()
        |> post(~p"/contact", %{@valid | "message" => "Another one"})
        |> html_response(200)

      assert html =~ "Give it a few minutes before sending another."
      assert_no_email_sent()
    end

    test "dropping the session doesn't get a second message through", %{conn: conn} do
      post(conn, ~p"/contact", @valid)
      assert_email_sent()

      # A fresh conn is a sender who cleared their cookies. The wait is held on
      # the server against their address, so it applies to them all the same.
      html =
        build_conn()
        |> post(~p"/contact", %{@valid | "message" => "Another one"})
        |> html_response(200)

      assert html =~ "Give it a few minutes before sending another."
      assert_no_email_sent()
    end

    test "the form stops taking messages once the hour's worth is in", %{conn: conn} do
      # Fill the window from addresses that aren't this sender's, so what stops
      # the next message is the ceiling on everyone rather than their own wait.
      for n <- 1..Limit.window_limit(), do: Limit.record("198.51.100.#{n}")

      html = conn |> post(~p"/contact", @valid) |> html_response(200)

      assert html =~ "The form has taken all it can for now."
      assert_no_email_sent()
    end

    test "the address counted is the one the proxy saw, not the one sent", %{conn: conn} do
      # A sender who forges the front of the forwarded list is still counted by
      # the entry the proxy appended, so the wait can't be typed around.
      conn
      |> put_req_header("x-forwarded-for", "203.0.113.9")
      |> post(~p"/contact", @valid)

      assert_email_sent()

      html =
        build_conn()
        |> put_req_header("x-forwarded-for", "10.0.0.1, 203.0.113.9")
        |> post(~p"/contact", %{@valid | "message" => "Another one"})
        |> html_response(200)

      assert html =~ "Give it a few minutes before sending another."
      assert_no_email_sent()
    end
  end

  describe "validation on its own" do
    test "trims the fields it accepts" do
      assert {:ok, message} =
               Contact.validate(%{
                 "name" => "  Ada  ",
                 "email" => "  ada@example.ac.uk ",
                 "message" => "  Hello  "
               })

      assert message.name == "Ada"
      assert message.email == "ada@example.ac.uk"
      assert message.message == "Hello"
    end

    test "whitespace alone is not a message" do
      assert {:error, errors} = Contact.validate(%{@valid | "message" => "     "})
      assert errors[:message]
    end
  end
end
