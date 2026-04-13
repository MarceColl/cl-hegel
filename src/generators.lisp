(in-package #:hegel)

(defun make-schema (type &rest pairs)
  "Build a generator schema alist. Drops pairs with nil values."
  (cons (cons "type" type)
        (loop for (key value) on pairs by #'cddr
              when value collect (cons key value))))

(defun gen-integer (&key min-value max-value)
  (make-schema "integer" "min_value" min-value "max_value" max-value))

(defun gen-boolean ()
  (make-schema "boolean"))

(defun gen-string (&key min-size max-size)
  (make-schema "string" "min_size" min-size "max_size" max-size))

(defun gen-list (elements &key min-size max-size)
  (make-schema "list" "elements" elements "min_size" min-size "max_size" max-size))

(defun gen-one-of (&rest schemas)
  (make-schema "one_of" "generators" schemas))

(defun gen-constant (value)
  (make-schema "constant" "value" value))

(defun gen-sampled-from (&rest values)
  (make-schema "sampled_from" "values" values))
