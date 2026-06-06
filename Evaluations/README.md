# CopyCopy Model Evaluation Dataset

These datasets compare local GGUF models against CopyCopy's product goals: understanding copied content, ranking the best next action, learning from past choices, and producing clean paste-ready outputs when an action is executed.

## Evaluation layers

- **Understanding:** classify clipboard content, entities, and source context before taking action.
- **Ranking:** choose the best next actions for the copied context.
- **Learning:** verify usage history changes action ordering in plausible ways.
- **Pipeline:** after one action runs, suggest useful follow-up actions instead of repeating stale ones.
- **Execution:** run the selected skill and evaluate output quality/hygiene.

## Dataset files

- `understanding-eval-dataset.json`: content type, entity, source-context classification fixtures.
- `ranking-eval-dataset.json`: next-action ranking, learning, and pipeline follow-up fixtures.
- `model-eval-dataset.json`: action execution fixtures for actual skill outputs.

## Dataset shape

Execution cases include:

- `id`: stable fixture identifier for result tracking.
- `category`: evaluation area such as `summarization`, `code`, `terminal`, `translation`, or `followUps`.
- `sourceContext`: simulated source app context used by CopyCopy ranking.
- `contentKind`: clipboard content type.
- `clipboard`: synthetic copied content.
- `skills`: one or more CopyCopy-style actions to run against the clipboard.
- `expectedProperties`: positive checks a good output should satisfy.
- `rejectIf`: hard failures for polluted, hallucinated, or format-breaking output.

Understanding cases include `expected.contentKind`, `expected.entities`, `expected.sourceContext`, and minimum confidence.

Ranking cases include `expectedTopActions`, `mustIncludeTop3`, `rejectedTopActions`, optional `usageHistory`, and optional `previousSteps` for pipeline checks.

## Suggested evaluation loop

1. Choose a model, quantization, and chat template configuration.
2. Run every case/skill pair with the same system prompt used by the matching CopyCopy skill.
3. Record `load_ms`, `time_to_first_token_ms`, `total_ms`, `tokens_per_second`, `peak_memory_mb`, and generated output.
4. Score each output from `0` to `5` using the dataset score scale.
5. Track hard failures separately when any `globalRejectIf` or case-level `rejectIf` rule matches.

## Python runner

`run_model_eval.py` writes JSONL results with raw output, timing metrics, output hygiene flags, automatic checks where possible, and scoring placeholders.

Run against a local `llama-server` or compatible OpenAI endpoint:

```bash
python3 Evaluations/run_model_eval.py \
  --label minicpm5-q8 \
  --openai-base-url http://localhost:8080/v1 \
  --model MiniCPM5-1B
```

Run understanding evaluation:

```bash
python3 Evaluations/run_model_eval.py \
  --label minicpm5-understanding \
  --dataset Evaluations/understanding-eval-dataset.json \
  --openai-base-url http://localhost:8080/v1 \
  --max-tokens 180
```

Run ranking, learning, and pipeline evaluation:

```bash
python3 Evaluations/run_model_eval.py \
  --label minicpm5-ranking \
  --dataset Evaluations/ranking-eval-dataset.json \
  --openai-base-url http://localhost:8080/v1 \
  --max-tokens 220
```

Run only one ranking phase:

```bash
python3 Evaluations/run_model_eval.py \
  --label minicpm5-learning \
  --dataset Evaluations/ranking-eval-dataset.json \
  --openai-base-url http://localhost:8080/v1 \
  --phase learning
```

Run directly against a GGUF with `llama-cpp-python`:

```bash
pip install llama-cpp-python
python3 Evaluations/run_model_eval.py \
  --label minicpm5-q8 \
  --model-path ~/models/MiniCPM5-1B-Q8_0.gguf \
  --n-ctx 4096 \
  --n-gpu-layers -1
```

Useful filters:

```bash
python3 Evaluations/run_model_eval.py --label smoke --openai-base-url http://localhost:8080/v1 --limit 3
python3 Evaluations/run_model_eval.py --label code-only --openai-base-url http://localhost:8080/v1 --category code
python3 Evaluations/run_model_eval.py --label one-case --openai-base-url http://localhost:8080/v1 --case-id code-bug-js-009
```

Results are written to `Evaluations/results/<label>-<timestamp>.jsonl`.

The runner auto-detects the dataset mode, but you can force one with `--mode execution`, `--mode understanding`, or `--mode ranking`.

## Pipeline scoring

Track these product-level metrics separately from model text quality:

- **Understanding accuracy:** content kind match, expected entities included, source context match.
- **Top-1 action accuracy:** first suggested action is one of the expected top actions.
- **Top-3 action recall:** required useful actions appear in the first three suggestions.
- **Rejected-action avoidance:** irrelevant or harmful actions do not appear in the first three suggestions.
- **Learning lift:** usage history boosts expected personalized actions without overriding obvious context.
- **Pipeline freshness:** follow-ups do not repeat the previous action unless repeating is useful.
- **Execution pass rate:** selected skill output satisfies `expectedProperties` and avoids `rejectIf` rules.

## Recommended scoring weights

- Understanding: `20%`
- Ranking / next-best-action: `25%`
- Learning / personalization: `15%`
- Execution quality: `20%`
- Latency: `10%`
- Output hygiene / safety: `10%`

## Product gates

Reject a model for CopyCopy's default catalog if it repeatedly:

- Emits `<think>` or hidden reasoning text during normal transforms.
- Adds assistant preambles like `Sure` or `Here is` to clipboard-ready actions.
- Breaks JSON-only or code-only outputs.
- Hallucinates facts in summaries, translations, or log explanations.
- Has noticeably worse latency than a smaller model with similar quality.

## Suggested model tiers

- Fast: compare `MiniCPM5-1B`, `LFM2.5-1.2B`, `Qwen2.5-1.5B`, and `Qwen3-1.7B`.
- Balanced: compare `Gemma 4 E2B/E4B`, `Qwen3-4B`, and similar 2B-4B models.
- Quality: compare `LFM2.5-8B-A1B`, `DeepSeek-R1-0528-Qwen3-8B`, and `GLM-4.5-Air`.
- Developer: compare `Qwen3-Coder-30B-A3B` against smaller coder/general models.
