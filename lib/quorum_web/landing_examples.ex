defmodule QuorumWeb.LandingExamples do
  @moduledoc """
  The sample questions the landing page's feed card cycles through.

  Illustrative, not real data. A mix of anonymous and named askers, because both
  are ordinary in a room, and vote counts that read like a real queue rather than
  a demo with round numbers.
  """

  @questions [
    %{
      votes: 31,
      name: nil,
      body: "If a system reports being conscious, what would count as evidence that it isn't?"
    },
    %{
      votes: 24,
      name: "Amara O.",
      body:
        "You said functionalism survives the China brain objection. Doesn't that just move the problem?"
    },
    %{votes: 18, name: nil, body: "Can we separate the hard problem from the meta-problem?"},
    %{
      votes: 27,
      name: "Tobias L.",
      body:
        "How does a supervisor decide whether to restart a child, and what happens to its links?"
    },
    %{
      votes: 14,
      name: nil,
      body: "What's the difference between a link and a monitor, and when would you want both?"
    },
    %{
      votes: 22,
      name: "Priya N.",
      body:
        "Why is the mailbox unbounded by default? Doesn't that move the failure somewhere worse?"
    },
    %{
      votes: 9,
      name: nil,
      body: "Does the scheduler preempt a process in the middle of a long list comprehension?"
    },
    %{
      votes: 16,
      name: "Kwame B.",
      body: "Is it ever correct to catch an exit rather than let the process die?"
    },
    %{
      votes: 11,
      name: nil,
      body: "Could you go over the reduction count example from last week again?"
    },
    %{
      votes: 35,
      name: "Yusuf A.",
      body: "At what point does the epistemic gap argument stop being about knowledge?"
    },
    %{votes: 7, name: nil, body: "Will the distributed section be on the exam?"},
    %{
      votes: 29,
      name: "Lena K.",
      body: "If qualia are functional states, what work is the word doing that 'state' doesn't?"
    },
    %{
      votes: 13,
      name: nil,
      body: "How do you decide between one_for_one and rest_for_one in practice?"
    },
    %{
      votes: 20,
      name: "Sofia R.",
      body: "You mentioned back-pressure twice. What breaks first when it isn't there?"
    },
    %{
      votes: 8,
      name: nil,
      body: "Is the zombie argument doing any work that conceivability alone doesn't?"
    },
    %{
      votes: 25,
      name: "Daniel M.",
      body: "Can two processes share memory in any way, or is copying the whole story?"
    },
    %{
      votes: 12,
      name: nil,
      body: "What does soft real-time guarantee, and what does it leave open?"
    },
    %{
      votes: 17,
      name: "Ngozi E.",
      body: "Does the multiple realisability argument survive if we fix the substrate?"
    },
    %{
      votes: 10,
      name: nil,
      body: "When would you reach for a GenServer instead of a plain process?"
    },
    %{
      votes: 21,
      name: "Haruto S.",
      body: "Is there a case where letting it crash is the wrong instinct?"
    }
  ]

  @doc "Every example, for the client to cycle through."
  def all, do: @questions

  @doc "One example to render before any JavaScript runs, so the card is never empty."
  def sample, do: Enum.random(@questions)

  @doc """
  How long ago a question was asked: anywhere from 30 seconds to 15 minutes,
  phrased the way the feed phrases it.
  """
  def ago(seconds) when seconds < 60, do: "#{seconds} seconds ago"
  def ago(seconds) when seconds < 120, do: "1 minute ago"
  def ago(seconds), do: "#{div(seconds, 60)} minutes ago"

  @doc "A random age in that range."
  def random_age, do: ago(Enum.random(30..900))

  @doc "What to call the asker."
  def asker(name), do: QuorumWeb.Wording.name_or_anon(name)
end
