# facemask

A line face that floats above the Mac screen. It draws eyes, brows, a nose, and a mouth, and talks with a local Ollama model.

macOS 14 or later is required. If `.env` names an API, that model is used. Otherwise the app uses Ollama on this computer (`http://127.0.0.1:11434`).

## Start

From a terminal, move into this repository folder and run:

```bash
swift run
```

Two things appear:

- A line face on the screen
- A small face icon at the right of the menu bar

Nothing is added to the Dock. The face window has no close button. The menu-bar icon shows whether the app is already running. Running it again while that icon is present opens another face.

## Quit

1. Click the small face icon in the menu bar at the top of the screen.
2. Click **Quit**.

Moving the face off screen or switching to another app leaves the app running. Quit only from this menu. After editing `.env`, quit and start the app again.

## Use

Type a message in the field under the face and press Return. The microphone on the left starts a spoken conversation. After you pause, the words are sent, and listening starts again once the reply has been read aloud. Press the microphone again to stop voice input. It also stops after 30 seconds of silence. The first press asks for microphone and speech-recognition permission.

- While a reply is on the way, the face is thinking and the brows look curious.
- When a reply arrives, the emotion on the first line changes the brows, and the rest is read aloud. During that, the face is speaking.
- When reading finishes, the face returns to idle. If you sent the message by voice, it starts listening again.

Drag the face to move the window. When it is not in a conversation, clicking the face cycles through idle, thinking, and speaking.

**Emotion** in the menu can lock an expression. **Auto** follows the conversation again.

| Emotion | Look |
| --- | --- |
| calm | Calm |
| curious | Curious |
| surprised | Surprised |
| skeptical | Skeptical. One brow goes up |
| concerned | Concerned. The inner brows come together |

The model writes only one of those words on the first line, then the words it will say. Those words are in English.

## Model

An API in the repository `.env` is used instead of Ollama. It accepts the same shape as the OpenAI API. OpenRouter and Groq use that shape too.

```bash
AI_BASE_URL=https://api.openai.com/v1
AI_API_KEY=sk-...
AI_MODEL=gpt-4o
```

If `AI_BASE_URL` is empty, the app uses `https://api.openai.com/v1`. `.env` is not committed. Only the example is in `.env.example`. Restart the app after changing the values.

`gpt-5` and `gpt-6` models search the web themselves when a question needs current facts. They do not search for talk that does not need it, such as a greeting. The face reads only the spoken text, not code or charts. Replies are in English.

Without `.env`, the app uses Ollama. `FACEMASK_MODEL` selects that local model. Otherwise it picks the first installed model in this order: `qwen3:latest`, `qwen2.5:14b`, `qwen2.5:14b-ctx`.

If Ollama is off, or the key or model name is missing, a short note appears under the face. The connected model name is shown in the menu bar.
