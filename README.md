# CL-HEGEL

A Common Lisp [Hegel](https://hegel.dev/) client library to bring Hypothesis property-based testing into Common Lisp.

## Warning

This software is BETA quality, layered on top of a beta release of Hegel, so expect paper cuts and broken stuff.

## Prerequisites

[uv](https://docs.astral.sh/uv/) must be installed. cl-hegel spawns `hegel-core` via `uv tool run`.

## Usage

### Raw

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

### Rove

We also have a (fairly barebones) integration with Rove. Will be improved over time.

```lisp
(ql:quickload :cl-hegel.rove)

(defun wrong-add (a b)
  (if (= a 0)
      (+ b 1)
      (+ a b)))

(deftest wrong-add
   (property "wrong-add works like +" ((a (integers))
                                       (b (integers)))
       (assert (= (wrong-add a b)) (+ a b)) ))
   
```

### Other testing libs

Not yet integrated, feel free to open a PR.
