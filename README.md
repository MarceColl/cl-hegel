# CL-HEGEL

A Common Lisp [Hegel](https://hegel.dev/) client library to bring Hypothesis property-based testing into Common Lisp.

## Warning

This software is BETA quality, layered on top of a beta release of Hegel, so expect paper cuts and broken stuff.

## Prerequisites

[uv](https://docs.astral.sh/uv/) must be installed. cl-hegel spawns `hegel-core` via `uv tool run`.

## Usage

```lisp
(ql:quickload :cl-hegel)

(hegel:run-property "sort is idempotent"
  (lambda ()
    (let* ((xs (hegel:generate (hegel:gen-list (hegel:gen-integer))))
           (sorted (sort (copy-seq xs) #'<)))
      (assert (equal sorted (sort (copy-seq sorted) #'<)))))
  :test-cases 100)
```

`run-property` spawns `hegel-core` on first use, returns a `test-result` on success, signals `property-failed` on failure.

## Generators

```lisp
(gen-integer &key min-value max-value)
(gen-boolean)
(gen-string &key min-size max-size)
(gen-list elements &key min-size max-size)
(gen-one-of &rest schemas)
(gen-constant value)
(gen-sampled-from &rest values)
```

Generators compose: `(gen-list (gen-one-of (gen-integer) (gen-string)))`.

## Filtering

`assume` skips test cases that don't meet a precondition:

```lisp
(hegel:assume (evenp x))
```

## Failure and replay

`property-failed` carries `name`, `seed`, and `test-cases-run`. Pass `:seed` back to `run-property` to reproduce a failure. Hegel's database automatically replays known failures on subsequent runs.
