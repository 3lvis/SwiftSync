# Voice

How we write the prose this repo produces — PRs, commit messages, code comments, docs, log lines, and the
error and diagnostic copy a consumer reads. Names in code are settled by [Names](#names) below, which
carries the Swift API Design Guidelines whole.

We write plainly and lead with the answer, so a reader gets the point from the first sentence and can stop
there. We say what a thing does and what it unlocks, in its own terms. We reach for one real example — an
egg breaks, the customer reorders, support credits that one egg, so 0.8 cases go to picking — rather than a
paragraph of definition. Anything with an order gets numbered steps, because you follow them one-handed. We
cut harder than feels finished, because the diff, the screenshot and the ticket each carry their share. And
we are honest in the same breath as ambitious: the framing leads with what a decision unlocks, the numbers
stay real. **Voice is constant; tone flexes** — empathetic on an error, lighter on a win.

That is the whole thing. The rules below are those sentences as specifics, for when a line feels wrong and
you want to know why.

## Names

Every name in code follows the [Swift API Design
Guidelines](https://www.swift.org/documentation/api-design-guidelines/). They are reproduced here, so a
naming question is answered by reading this section. Their scope is the API a name belongs to; a test method
is named for the behaviour it holds.

### What decides every name

> "Clarity at the point of use is your most important goal."
> "Clarity is more important than brevity."
> "Include all the words needed to avoid ambiguity for a person reading code where the name is used."
> "Omit needless words. Every word in a name should convey salient information at the use site."

A declaration is written once and read at every call site, so the call site decides. `employees.remove(at: x)`
over `employees.remove(x)`; `allViews.remove(cancelButton)` needs the word it has.

### What part of speech

> "The names of other types, properties, variables, and constants should read as nouns."
> "Those without side-effects should read as noun phrases."
> "Those with side-effects should read as imperative verb phrases."
> "Uses of Boolean methods and properties should read as assertions about the receiver when the use is nonmutating."
> "Protocols that describe what something is should read as nouns."
> "Protocols that describe a capability should be named using the suffixes `able`, `ible`, or `ing`."

`x.distance(to: y)` and `i.successor()` read as nouns; `x.sort()` and `print(x)` command. `x.isEmpty` and
`line1.intersects(line2)` assert. `Collection` says what a thing is; `Equatable` and `ProgressReporting` say
what it can do.

### A pair that mutates and a pair that copies

> "Name Mutating/nonmutating method pairs consistently."
> "When the operation is naturally described by a verb, use the verb's imperative for the mutating method and apply the 'ed' or 'ing' suffix to name its nonmutating counterpart."
> "When the operation is naturally described by a noun, use the noun for the nonmutating method and apply the 'form' prefix to name its mutating counterpart."

`x.sort()` beside `x.sorted()`, `s.stripNewlines()` beside `s.strippingNewlines()`, `y.formUnion(z)` beside
`x.union(z)`.

### Roles, and where the type says little

> "Name variables, parameters, and associated types according to their roles, rather than their type constraints."
> "Compensate for weak type information to clarify a parameter's role."

`var greeting = "Hello"` over `var string = "Hello"`. Where a parameter's type is `NSObject` or `String`, the
label carries the role: `add(_ observer: NSObject, for keyPath: String)`.

### Fluent use

> "Prefer method and function names that make use sites form grammatical English phrases."
> "Begin names of factory methods with `make`."
> "Name functions and methods according to their side-effects."

`x.insert(y, at: z)` reads as a sentence; `x.insert(y, position: z)` reads as a form.

### Terminology

> "Avoid obscure terms if a more common word conveys meaning just as well."
> "Stick to the established meaning if you do use a term of art."
> "Avoid abbreviations. Abbreviations, especially non-standard ones, are effectively terms-of-art."
> "Embrace precedent."

`Array` over `List`, because the culture already settled it. An abbreviation earns its place when a web search
finds its meaning — `sin(x)` qualifies.

### Argument labels

> "Omit all labels when arguments can't be usefully distinguished."
> "In initializers that perform value preserving type conversions, omit the first argument label."
> "In 'narrowing' type conversions, a label that describes the narrowing is recommended."
> "When the first argument forms part of a prepositional phrase, give it an argument label."
> "The argument label should normally begin at the preposition."
> "Otherwise, if the first argument forms part of a grammatical phrase, omit its label, appending any preceding words to the base name."
> "If the first argument doesn't form part of a grammatical phrase, it should have a label."
> "Arguments with default values can be omitted and should always have labels."
> "Label all other arguments."

`min(number1, number2)`; `String(veryLargeNumber)` beside `init(truncating source: UInt64)`;
`x.removeBoxes(havingLength: 12)`; `view.dismiss(animated: false)`.

### Conventions

> "Follow case conventions. Names of types and protocols are `UpperCamelCase`. Everything else is `lowerCamelCase`."
> "Acronyms and initialisms that commonly appear as all upper case should be uniformly up- or down-cased."
> "Prefer methods and properties to free functions."
> "Methods can share a base name when they share the same basic meaning or when they operate in distinct domains."
> "Avoid 'overloading on return type' because it causes ambiguities in the presence of type inference."
> "Choose parameter names to serve documentation."
> "Prefer to locate parameters with defaults toward the end of the parameter list."
> "Label tuple members and name closure parameters where they appear in your API."

`var utf8Bytes: [UTF8.CodeUnit]` and `var radarDetector: RadarScanner` show the two halves of the acronym
rule. A free function earns its place where an obvious `self` is absent, where the generic is unconstrained,
or where function syntax is the domain's own notation.

## The rules

### Lead with what it unlocks

State what a thing is, does, and makes possible, and let that stand on its own. Turn a negative foil into
its positive core — "X isn't A, it's B" becomes "B" — and drop trailing "…, not Y" clauses along with the
concession that opens one: "it is binding since it loads into every session" says what "it loads into every
session, whether or not it is relevant" was circling. Justify a choice by what it gives: "two targets let
each brand ship on its own" in place of "a single target would force a matrix". Treat a deliberate scope
choice as a strength to lean into.

oida's `document_says_what_is` fails the lint on a negation standing in a root document's own voice; code,
quoted specimens and links are the document showing something rather than saying it. A PR body and a
comment hold themselves to the same shape, on the writer's word rather than the linter's.

### Put the conclusion first

Say the answer, then the reasoning, and close with the next step. A PR body leads with the ticket link,
states what is now true and why, and holds only conclusions — the diff carries the mechanism. A spike that
ends in "no" is a sentence for the commit log. *Good:* "Cart totals double-counted deposits; this nets them
once."

A commit message is the same shape, smaller: a first line saying what is now true, present tense, under
about seventy characters. A body earns its place when the reasoning would otherwise be lost — a constraint
that forced the approach, an alternative that failed, a number you had to measure.

### Say each thing once

A fact lives in the one place that owns it, and everywhere else references it. ARCHITECTURE holds the
destination and PLAN the distance to it; a duplicated line rots out of sync.

### Use plain words

Say what a thing does in the words a person would use, and read it aloud to check. This covers our own
jargon: "the app supplies the concrete fan-out" becomes "one event reaches all three trackers". Keep a term
of art only where the document defines it.

A handful of words are retired outright, and oida's `document_avoids_retired_words` holds the list. A word
joins it once the repo reads better without it.

### Let the code carry the count

A number that describes today rots on its own: a case is added, a gate is added, and the document goes wrong
while nobody touches it. Name the thing and let the code answer how many — `middleware.py` holds the
capability gates, however many there are.

Two kinds of number stay. One that records what happened, since that keeps being true: thirty files broke
that afternoon. And one that is a contract rather than a tally: two brands, one navigator.

### Give structure only when it earns its place

Headers suit a reference document. A table earns its place when its content is a grid, two axes deep. A
pair of columns becomes prose when a reader takes it in one pass, and a titled line each when they look one
entry up.

### Number anything with an order

"Install the test app, sign in, then place the order" is three steps, so write `1.`, `2.`, `3.`, one action
each — you follow it with a phone in your other hand and you need to find step five again. Bullets are for
a set whose order is free. A paragraph of steps reads fine and is worse to work from.

### Show one real example

*Good:* "an egg breaks, the customer reorders, support credits that one egg → 0.8 cases go to picking" —
over "handles partial-refund reconciliation edge cases." A scenario proves you understand the case; a
definition only proves you can name it.

### Write in the active voice

Name the actor and let it do the doing, so a reader knows who acts. *Good:* "Signs with the dedicated key,
so deleting that secret revokes every token at once." A line whose subject went missing — "the token is
signed" — hides the one fact the sentence exists to carry.

### Cut harder than feels finished

The test is mechanical: delete a sentence and read the paragraph again. If it still says everything it did,
the sentence stays deleted — which is the fate of most sentences that open with a wind-up, restate the
previous one, or reassure the reader that you were thorough. When something reads as alarming, name what
stays safe: "read-only, so your data is intact".

**Try deleting before you try rewriting**, and read the whole sentence before you touch a clause. A line
that wants reworking is usually restating its neighbour, so the paragraph reads better with it gone than
with it fixed — and a clause edited in isolation is how "the block has a registered destination" ends up
saying the opposite of the paragraph around it.

### A rewrite owns the fact

Tightening a line makes you its author, so check what it claims while you are in there. A close read
surfaces rot — a path that moved, a count that drifted from the table under it, a tool renamed a month ago
— and it is also where a fact breaks, through an inverted clause or a sentence trimmed to a fragment. Fix
what you find, then re-read the paragraph whole.

### Back a claim with evidence

A UI change leads with a before/after screenshot. A real, honest number beats an adjective, and it beats
invented precision too: "around 30k", "it's rare".

### Name a control or a heading by what it does

A control says exactly what happens: "Publish" produces a "Published" toast. Where the reader cares about
the outcome, the name states it — "Save draft" over "Submit form", "Delete order" over "Confirm". A heading
is a label too, so it names its contents in as few words as that takes: "Gotchas" over "What only this repo
can tell you".

### Comment what only prose can say

External knowledge, a non-obvious *why*, a gotcha or a contract, a TODO with enough context to resume. A
name, a type, or a test carries the rest.

The failure mode is a comment that narrates the lines under it — "Never describe the code", as Google's
Python style guide puts it, since the reader knows the language better than you and reads those lines
anyway. A docstring restating its own name goes with them. **A comma is the tell**: the clause after it
usually says again what the code just said, so cut to the single clause carrying behaviour the code lacks.
*Good:* "The command reports success whatever APNs answered." *Cut from:* "The command reports success
whatever APNs answered; the delivery row is the truth." A paragraph standing above a few statements is
prose that escaped into a file where the code beside it says more.

### A script carries its own usage

`--help` is a script's own documentation, so its header holds the commands in aligned columns and the
prerequisites it assumes. A document naming that script states those prerequisites and points at it,
because the header is the copy that stays current while a second one drifts. Where a value differs per
machine — a simulator, a checkout — the script takes it from the environment and the failure says which:
"SIMULATOR_UDID has to name a booted simulator: export SIMULATOR_UDID=$(xcrun simctl list devices | ...)".

### In an error, state the effect and offer the fix

An error has three faces, and each answers to one owner.

**What a person reads** is ours. State the effect in plain, specific terms, reassure where the reassurance
is honest, and name the action. *Good:* "Loading your books failed — they're safe. Try again." A title
carries the effect, so "Something went wrong" earns a rewrite; a button carries its verb, so "OK" becomes
"Try again". A transient failure often leaves the cause unknowable, and the effect plus a retry beats a
guess at why; a field a person can fix names the fix inline — "Password needs 8 characters or more". A
screen holding a failure also carries a reference the reader can quote, so a screenshot reaches the recorded
error. Blame, apology and hedging each cost the reader time: "invalid", "sorry", "usually" go.

**What we read in a log** is ours too, and the same shape: what was refused, plus enough to find it.
*Good:* "The tree refused a screen's request: screenCovered".

**The type and its cases** are code, so the rule at the top of this page governs them.

---

Kept by use: a rule lands here the day writing goes wrong in a way worth preventing twice, and stays while
it still catches something. A rule a test can hold moves into the test and leaves. Every document here is
held to this one, this one included.
