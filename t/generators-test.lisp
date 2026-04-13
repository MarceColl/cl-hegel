(in-package #:hegel/tests)

(def-suite generators-suite
  :description "Generator schema constructor tests"
  :in hegel-suite)

(in-suite generators-suite)

(defun schema-type (schema)
  (cdr (assoc "type" schema :test #'string=)))

(defun schema-field (schema field)
  (cdr (assoc field schema :test #'string=)))

;;; gen-integer

(test gen-integer-no-bounds
  (let ((s (gen-integer)))
    (is (string= "integer" (schema-type s)))
    ;; No min/max keys when unbounded
    (is (null (assoc "min_value" s :test #'string=)))
    (is (null (assoc "max_value" s :test #'string=)))))

(test gen-integer-with-bounds
  (let ((s (gen-integer :min-value 0 :max-value 100)))
    (is (string= "integer" (schema-type s)))
    (is (= 0 (schema-field s "min_value")))
    (is (= 100 (schema-field s "max_value")))))

;;; gen-boolean

(test gen-boolean-schema
  (let ((s (gen-boolean)))
    (is (string= "boolean" (schema-type s)))))

;;; gen-string

(test gen-string-no-bounds
  (let ((s (gen-string)))
    (is (string= "string" (schema-type s)))))

(test gen-string-with-bounds
  (let ((s (gen-string :min-size 1 :max-size 10)))
    (is (= 1 (schema-field s "min_size")))
    (is (= 10 (schema-field s "max_size")))))

;;; gen-list

(test gen-list-schema
  (let ((s (gen-list (gen-integer))))
    (is (string= "list" (schema-type s)))
    (is (string= "integer" (schema-type (schema-field s "elements"))))))

(test gen-list-with-bounds
  (let ((s (gen-list (gen-boolean) :min-size 2 :max-size 5)))
    (is (= 2 (schema-field s "min_size")))
    (is (= 5 (schema-field s "max_size")))))

;;; gen-one-of

(test gen-one-of-schema
  (let ((s (gen-one-of (gen-integer) (gen-string))))
    (is (string= "one_of" (schema-type s)))
    (is (= 2 (length (schema-field s "generators"))))))

;;; gen-constant

(test gen-constant-schema
  (let ((s (gen-constant 42)))
    (is (string= "constant" (schema-type s)))
    (is (= 42 (schema-field s "value")))))

;;; gen-sampled-from

(test gen-sampled-from-schema
  (let ((s (gen-sampled-from "a" "b" "c")))
    (is (string= "sampled_from" (schema-type s)))
    (is (equal '("a" "b" "c") (schema-field s "values")))))
