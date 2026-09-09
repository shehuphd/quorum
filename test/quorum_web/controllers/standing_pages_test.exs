defmodule QuorumWeb.StandingPagesTest do
  use QuorumWeb.ConnCase

  import Swoosh.TestAssertions

  alias Quorum.Contact

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

      assert html =~ "Draft."
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

      assert html =~ "Give it a minute before sending another."
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
