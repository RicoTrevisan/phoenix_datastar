---
name: datastar-attributes
description: "Reference for all Datastar HTML data-* attributes, actions, and expression syntax. Consult this when writing templates with Datastar attributes to avoid syntax errors like data-on-click (wrong) vs data-on:click (correct)."
---

# Datastar Attribute Reference

## Critical Syntax Rules

Datastar attributes use **colons** (`:`) to separate the attribute name from its key, and **double underscores** (`__`) for modifiers. Getting this wrong is the most common mistake.

```html
<!-- ✅ CORRECT: colon separates plugin name from key -->
<button data-on:click="$count++">Click</button>
<input data-bind:value="name" />
<div data-attr:disabled="$loading"></div>
<div data-class:active="$isActive"></div>

<!-- ❌ WRONG: hyphens instead of colons -->
<button data-on-click="$count++">INVALID</button>
<input data-bind-value="name">INVALID</input>
<div data-attr-disabled="$loading">INVALID</div>
```

Modifiers use double underscores (`__`), with sub-modifiers separated by dots (`.`):

```html
<!-- ✅ CORRECT: double underscore for modifiers -->
<div data-on:click__debounce.500ms="@post('/save')">Save</div>
<div data-init__once="@get('/stream')"></div>
<div data-on-interval__duration.2s="$tick++"></div>

<!-- ❌ WRONG: single underscore or other separators -->
<div data-init_once="...">INVALID</div>
```

## Signal Access: `$` vs Bare Names

- **Expressions** (evaluated as JavaScript): use `$signalName` to read signal values.
- **`data-bind`**: takes a bare signal **name** (no `$` prefix). It creates/references a signal by name.
- **`data-indicator`**: takes a bare signal **name** (no `$` prefix).
- **`data-ref`**: takes a bare signal **name** (no `$` prefix).

```html
<!-- ✅ CORRECT: data-bind takes a signal NAME, no $ -->
<input data-bind="username" />
<input type="checkbox" data-bind="agreed" />
<select data-bind="selectedOption">...</select>

<!-- ❌ WRONG: $ prefix in data-bind -->
<input data-bind="$username" />

<!-- ✅ CORRECT: expressions use $ to READ signal values -->
<span data-text="$username"></span>
<div data-show="$agreed"></div>
<button data-on:click="@post('/save', {name: $username})">Save</button>
```

## Attributes

### Signals & State

#### `data-signals`
Patches signals into the existing signal store. Value is a JavaScript object expression.

```html
<!-- Initialize signals -->
<div data-signals="{count: 0, name: 'test'}"></div>

<!-- Namespaced signals (creates nested object) -->
<div data-signals:form="{name: '', email: ''}"></div>

<!-- Only set if signal doesn't already exist -->
<div data-signals__ifmissing="{count: 0}"></div>
```

#### `data-computed`
Creates a signal whose value is derived from an expression. Re-evaluates when dependencies change.

```html
<div data-computed:fullName="$firstName + ' ' + $lastName"></div>
<div data-computed:total="$price * $quantity"></div>
```

#### `data-ref`
Creates a signal that is a reference to the DOM element. Takes a bare signal name.

```html
<canvas data-ref="myCanvas"></canvas>
<!-- Access in expressions as $myCanvas -->
```

### Rendering

#### `data-text`
Binds the text content of an element to an expression.

```html
<span data-text="$count"></span>
<p data-text="$firstName + ' ' + $lastName"></p>
<span data-text="`Total: ${$price * $qty}`"></span>
```

#### `data-show`
Shows or hides an element based on a boolean expression (toggles `display: none`).

```html
<div data-show="$isVisible">Conditionally visible</div>
<div data-show="$items.length > 0">Has items</div>
```

#### `data-attr`
Sets HTML attributes reactively. Use colon for single attribute, object for multiple.

```html
<!-- Single attribute -->
<button data-attr:disabled="$loading">Submit</button>
<img data-attr:src="$imageUrl" />
<a data-attr:href="$link">Link</a>

<!-- Multiple attributes via object -->
<input data-attr="{placeholder: $hint, maxlength: $max}" />
```

#### `data-class`
Adds or removes CSS classes based on boolean expressions.

```html
<!-- Single class -->
<div data-class:active="$isActive">Tab</div>
<div data-class:hidden="!$visible">Content</div>

<!-- Multiple classes via object -->
<div data-class="{'bg-red-500': $hasError, 'font-bold': $important}">Alert</div>
```

#### `data-style`
Sets inline CSS styles reactively.

```html
<!-- Single property -->
<div data-style:color="$textColor">Styled</div>
<div data-style:opacity="$fade"></div>

<!-- Multiple properties via object -->
<div data-style="{color: $textColor, fontSize: $size + 'px'}"></div>
```

### Input Binding

#### `data-bind`
Creates a signal and sets up **two-way data binding** between it and an element's value. Takes a bare signal **name** (no `$` prefix).

```html
<!-- Text input -->
<input type="text" data-bind="username" />

<!-- With key syntax (equivalent) -->
<input type="text" data-bind:value="username" />

<!-- Checkbox (boolean) -->
<input type="checkbox" data-bind="agreed" />

<!-- Radio buttons (share same signal name) -->
<input type="radio" name="color" value="red" data-bind="color" />
<input type="radio" name="color" value="blue" data-bind="color" />

<!-- Select -->
<select data-bind="country">
  <option value="us">US</option>
  <option value="uk">UK</option>
</select>

<!-- Textarea -->
<textarea data-bind="message"></textarea>

<!-- File input (signal value is an array of {name, contents, mime} objects) -->
<input type="file" data-bind="avatar" />
```

### Event Handling

#### `data-on`
Attaches an event listener. The key after the colon is the **event name**.

```html
<button data-on:click="$count++">Increment</button>
<input data-on:input="$search = evt.target.value" />
<form data-on:submit__prevent="@post('/submit')">...</form>
<div data-on:keydown__window="$key = evt.key"></div>
```

**Modifiers** (appended with `__`):
- `__prevent` — calls `evt.preventDefault()`
- `__stop` — calls `evt.stopPropagation()`
- `__window` — listens on `window` instead of the element
- `__once` — fires only once
- `__capture` — uses capture phase
- `__passive` — marks as passive listener
- `__debounce.Nms` — debounces by N milliseconds (e.g., `__debounce.500ms`)
- `__throttle.Nms` — throttles by N milliseconds
- `__viewtransition` — wraps in View Transitions API

```html
<input data-on:input__debounce.300ms="@post('/search', {q: $query})" data-bind="query" />
<button data-on:click__once="@post('/track')">Track</button>
```

#### `data-on-intersect`
Runs an expression when the element enters (or exits) the viewport.

```html
<div data-on-intersect="@post('/seen')">Lazy load</div>
<div data-on-intersect__once="$viewed = true">View tracker</div>
<div data-on-intersect__half="$halfVisible = true">50% visible</div>
<div data-on-intersect__full="$fullyVisible = true">100% visible</div>
<div data-on-intersect__exit="$left = true">Exited viewport</div>
```

#### `data-on-interval`
Runs an expression at a regular interval (default: 1000ms).

```html
<div data-on-interval="$tick++"></div>
<div data-on-interval__duration.2s="@get('/poll')"></div>
<div data-on-interval__duration.500ms="$elapsed += 0.5"></div>
```

#### `data-on-signal-patch`
Runs an expression whenever signals are patched (e.g., from SSE).

```html
<div data-on-signal-patch="console.log('signals updated')"></div>
```

### Lifecycle & Effects

#### `data-init`
Runs an expression once when the element is loaded into the DOM.

```html
<div data-init="@get('/api/data')"></div>
<div data-init__once="@get('/stream', {openWhenHidden: true})"></div>
<div data-init__delay.1s="$ready = true"></div>
```

#### `data-effect`
Runs an expression on load and re-runs whenever any referenced signals change.

```html
<div data-effect="document.title = `Count: ${$count}`"></div>
<div data-effect="$total = $price * $quantity"></div>
```

#### `data-indicator`
Creates a boolean signal that is `true` while a fetch request from this element is in flight. Takes a bare signal **name** (no `$` prefix).

```html
<button data-on:click="@post('/save')" data-indicator="saving">
  <span data-show="$saving">Saving...</span>
  <span data-show="!$saving">Save</span>
</button>

<!-- With key syntax -->
<button data-on:click="@post('/save')" data-indicator:value="saving">
  ...
</button>
```

### Debug

#### `data-json-signals`
Outputs a JSON-stringified view of all signals as the element's text content. Useful for debugging.

```html
<pre data-json-signals></pre>
<pre data-json-signals__terse></pre>  <!-- compact, no indentation -->
```

## Actions (Used in Expressions)

Actions are called with `@` prefix inside attribute expressions.

### Fetch Actions

```html
<!-- GET (does NOT send signals by default, openWhenHidden: false by default) -->
<div data-on:click="@get('/api/data')"></div>

<!-- POST (sends signals, openWhenHidden: true by default) -->
<button data-on:click="@post('/api/save')">Save</button>

<!-- PUT, PATCH, DELETE also available -->
<button data-on:click="@put('/api/update')">Update</button>
<button data-on:click="@patch('/api/partial')">Patch</button>
<button data-on:click="@delete('/api/remove')">Delete</button>
```

Fetch options (second argument):

```html
<button data-on:click="@post('/save', {
  headers: {'x-custom': 'value'},
  selector: '#target',
  openWhenHidden: true
})">Save</button>
```

### Other Actions

```html
<!-- @setAll: set all matching signals to a value -->
<button data-on:click="@setAll(false, {include: /^form\./})">Reset form</button>

<!-- @toggleAll: toggle all matching boolean signals -->
<button data-on:click="@toggleAll({include: /^checkbox/})">Toggle all</button>

<!-- @peek: read signals without subscribing to changes (use inside data-effect) -->
<div data-effect="console.log(@peek(() => $count))"></div>
```

## PhoenixDatastar Helpers

In PhoenixDatastar templates, use the `event/1,2` and `navigate/1,2` helpers instead of manually writing `@post` expressions:

```elixir
<!-- ✅ Use PhoenixDatastar helpers for events -->
<button data-on:click={event("increment")}>+1</button>
<button data-on:click={event("save", "name: $username")}>Save</button>

<!-- ✅ Use navigate for soft navigation -->
<button data-on:click={navigate("/dashboard")}>Go</button>

<!-- ✅ Or use the ds_link component -->
<.ds_link navigate="/dashboard">Dashboard</.ds_link>
```
