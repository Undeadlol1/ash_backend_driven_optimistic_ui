# On the wire

One tap, followed message by message, with the real data. The example is
the todo app from [How it works](how-it-works.md): completing a todo
ticks it and gives 10 XP.

The library defines two pieces of data: the rules (message 1) and the
answer's list (message 4). How they travel is your app's choice. Here
they travel as JSON over HTTP, and notifications over a WebSocket.

## 1. App start: the server sends the rules

The `:rules` action of `AshBackendDrivenOptimisticUi.RuleSet` returns:

```json
{
  "version": "5c1e09ab77d3f240",
  "rules": {
    "todo.complete": {
      "effects": [
        {
          "where": {"!": [{"var": "record.done"}]},
          "effects": [
            {"set": {"done": true}, "source": "declared"},
            {"push": {"event": "xp_awarded", "payload": {
              "amount": 10,
              "id": {"var": "ctx.push_ids.xp_awarded.complete"}
            }}}
          ]
        }
      ],
      "reactions": [
        {"on": "xp_awarded", "type": "user_level", "effects": [
          {"set": {"total_xp": {"+": [{"var": "record.total_xp"}, {"var": "event.amount"}]}},
           "source": "declared"}
        ]}
      ]
    }
  }
}
```

The app keeps this until `version` changes.

## 2. What the app holds before the tap

The todo, as the server sent it earlier. `ctx` came with it:

```json
{
  "id": "42",
  "title": "Buy milk",
  "done": false,
  "updated_at": "2026-10-25T18:03:00.123456Z",
  "ctx": {
    "push_ids": {
      "xp_awarded": {
        "complete": "todo:42:2026-10-25T18:03:00.123456Z:xp_awarded:complete"
      }
    }
  }
}
```

The user's level:

```json
{"id": "7", "total_xp": 120}
```

## 3. The tap

Nothing is sent yet. The app runs `todo.complete` on what it holds.

The `where` is true (`done` is false), so:

- the `set` gives the todo `"done": true`;
- the `push` becomes this event, which the app shows as a toast:

  ```json
  {
    "event": "xp_awarded",
    "payload": {
      "amount": 10,
      "id": "todo:42:2026-10-25T18:03:00.123456Z:xp_awarded:complete"
    }
  }
  ```

- the reaction gives the level `"total_xp": 130`.

The app remembers the id it showed.

## 4. The save and its answer

The request is your normal one, plus the ids the app showed:

```
PATCH /todos/42/complete
x-optimistic-ids: todo:42:2026-10-25T18:03:00.123456Z:xp_awarded:complete
```

The server runs the action. Before the action it called
`PushCollector.open()`, and after it
`PushCollector.drain_reconciliation(ids)`, which returns:

```json
{
  "pushes": [
    {
      "event": "xp_awarded",
      "payload": {
        "amount": 10,
        "id": "todo:42:2026-10-25T18:03:00.123456Z:xp_awarded:complete"
      }
    }
  ],
  "retracted": []
}
```

Your app puts that in the answer. Over HTTP, under `meta`:

```json
{
  "data": {"id": "42", "title": "Buy milk", "done": true},
  "meta": {
    "pushes": [
      {
        "event": "xp_awarded",
        "payload": {
          "amount": 10,
          "id": "todo:42:2026-10-25T18:03:00.123456Z:xp_awarded:complete"
        }
      }
    ],
    "retracted": []
  }
}
```

The app reads it:

- `pushes` has the id it already showed, so it shows nothing again.
- `retracted` is empty, so the guess stands.

## 5. The notifications

The server's notifiers send the same things over the WebSocket, as they
did before this library existed. The event:

```json
{
  "event": "xp_awarded",
  "payload": {
    "amount": 10,
    "id": "todo:42:2026-10-25T18:03:00.123456Z:xp_awarded:complete"
  }
}
```

Same id, so the app skips it. And the real records, which replace the
guesses:

```json
{"id": "42", "title": "Buy milk", "done": true, "updated_at": "2026-10-25T18:03:02.456789Z"}
```

```json
{"id": "7", "total_xp": 130}
```

The guess was right, so nothing on screen changes. The todo's
`updated_at` moved, so the next tap gets a new id.

## When the guess was wrong

The save worked, but the server gave no XP. The answer:

```json
{
  "data": {"id": "42", "title": "Buy milk", "done": true},
  "meta": {
    "pushes": [],
    "retracted": ["todo:42:2026-10-25T18:03:00.123456Z:xp_awarded:complete"]
  }
}
```

`retracted` names the event the app showed and the server did not send.
The app puts back what it held before the tap (`total_xp` is 120 again),
and the real todo arrives by notification with `"done": true`.

## When the save fails

The server answers with its usual error and no list:

```json
{"errors": [{"detail": "is already done"}]}
```

The app puts back what it held before the tap.

## When nothing was guessed

No ids sent and nothing pushed: `drain_reconciliation/1` returns `nil`,
and the answer is exactly what it was without this library.
