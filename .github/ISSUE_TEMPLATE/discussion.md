name: "💬 General Discussion"
about: Ask questions, share ideas, or talk about Parrot
labels: discussion
body:
  - type: markdown
    attributes:
      value: |
        Welcome to Parrot Discussions! Ask questions, share how you use Parrot, or suggest ideas.
  - type: textarea
    id: topic
    attributes:
      label: What's on your mind?
      description: Share your question, idea, or feedback.
    validations:
      required: true
  - type: dropdown
    id: category
    attributes:
      label: Category
      options:
        - Question
        - Idea
        - Show & Tell
        - Feedback
        - Other
    validations:
      required: true
