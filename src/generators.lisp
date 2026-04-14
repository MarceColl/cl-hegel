(defpackage #:hegel.generators
  (:use :cl)
  (:export
   :constants
   :sampled-from
   :one-of
   :nulls
   :booleans
   :integers
   :floats
   :strings
   :binaries
   :regexes
   :lists
   :dicts
   :tuples
   :emails
   :urls
   :domains
   :ipv4s
   :ipv6s
   :dates
   :times
   :datetimes))
   
(in-package #:hegel.generators)

(defun make-schema (type &rest pairs)
  "Build a generator schema alist. Drops pairs with nil values."
  (cons (cons "type" type)
        (loop for (key value) on pairs by #'cddr
              when value collect (cons key value))))

(defun constants (value)
  (make-schema "constant" "value" value))

(defun sampled-from (&rest values)
  (make-schema "sampled_from" "values" values))

(defun one-of (&rest schemas)
  (make-schema "one_of" "generators" schemas))

(defun nulls ()
  (make-schema "null"))

(defun booleans (p)
  (make-schema "boolean" "p" p))

(defun integers (&key min-value max-value)
  (make-schema "integer" "min_value" min-value "max_value" max-value))

(defun floats (&key min-value max-value allow-nan allow-infinity width exclude-min exclude-max)
  (make-schema "float" "min_value" min-value "max_value" max-value "allow_nan" allow-nan "allow_infinity" allow-infinity "width" width "exclude_min" exclude-min "exclude_max" exclude-max))

(defun strings (&key min-size max-size)
  ;; TODO: add characters schema
  (make-schema "string" "min_size" min-size "max_size" max-size))

(defun binaries (&key min-size max-size)
  (make-schema "binary" "min_size" min-size "max_size" max-size))

(defun regexes (pattern &key alphabet fullmatch)
  (make-schema "regex" "pattern" pattern "alphabet" alphabet "fullmatch" fullmatch))

(defun lists (elements &key (min-size 0) max-size (unique nil))
  (make-schema "list" "elements" elements "min_size" min-size "max_size" max-size))

(defun dicts (keys values &key (min-size 0) max-size)
  (make-schema "dict" "keys" keys "values" values "min_size" min-size "max_size" max-size))

(defun tuples (elements)
  (make-schema "tuple" "elements" elements))

(defun emails ()
  (make-schema "email"))

(defun urls ()
  (make-schema "url"))

(defun domains (&key max-length)
  (make-schema "domain" "max_length" max-length))

(defun ipv4s ()
  (make-schema "ipv4"))

(defun ipv6s ()
  (make-schema "ipv6"))

(defun dates ()
  (make-schema "date"))

(defun times ()
  (make-schema "time"))

(defun datetimes ()
  (make-schema "datetime"))
