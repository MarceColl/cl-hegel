(in-package #:hegel/tests)

(def-suite integration-suite
  :description "Integration tests against real hegel-core"
  :in hegel-suite)

(in-suite integration-suite)

(test handshake-with-real-hegel-core
  "Connect to hegel-core, perform handshake, close cleanly"
  (let ((conn (start-hegel-core)))
    (unwind-protect
         (progn
           (perform-handshake conn)
           (is (connection-handshake-done-p conn)))
      (hegel:close-connection conn))))

(test run-property-passing-integration
  "Run a trivially passing property against real hegel-core"
  (with-connection ()
    (let ((result (run-property "integers are numbers"
                   (lambda ()
                     (let ((x (generate (gen-integer))))
                       (assert (numberp x))))
                   :test-cases 10)))
      (is (test-result-passed result)))))

(test run-property-failing-integration
  "Run a failing property and verify property-failed is signaled"
  (with-connection ()
    (handler-case
        (progn
          (run-property "negative exists"
            (lambda ()
              (let ((x (generate (gen-integer :min-value -100 :max-value 100))))
                (assert (>= x 0))))
            :test-cases 100)
          (fail "Expected property-failed"))
      (property-failed (c)
        (is (stringp (property-failed-seed c)))
        (is (plusp (property-failed-test-cases-run c)))))))

(test generate-various-types-integration
  "Generate values of different types"
  (with-connection ()
    (let ((result (run-property "multi-type"
                   (lambda ()
                     (let ((i (generate (gen-integer :min-value 0 :max-value 10)))
                           (b (generate (gen-boolean)))
                           (s (generate (gen-string :max-size 5))))
                       (assert (typep i 'integer))
                       (assert (typep b 'boolean))
                       (assert (typep s 'string))))
                   :test-cases 10)))
      (is (test-result-passed result)))))

;;; Generator constraint tests

(test gen-integer-respects-bounds
  "gen-integer with min/max actually constrains generated values"
  (with-connection ()
    (let ((result (run-property "integer bounds"
                   (lambda ()
                     (let ((x (generate (gen-integer :min-value 10 :max-value 20))))
                       (assert (<= 10 x 20))))
                   :test-cases 50)))
      (is (test-result-passed result)))))

(test gen-string-generation
  "gen-string generates string values"
  (with-connection ()
    (let ((result (run-property "string gen"
                   (lambda ()
                     (let ((s (generate (gen-string))))
                       (assert (stringp s))))
                   :test-cases 50)))
      (is (test-result-passed result)))))

(test gen-constant-returns-exact-value
  "gen-constant always returns the specified value"
  (with-connection ()
    (let ((result (run-property "constant 42"
                   (lambda ()
                     (let ((x (generate (gen-constant 42))))
                       (assert (= x 42))))
                   :test-cases 10)))
      (is (test-result-passed result)))))

(test gen-sampled-from-returns-member
  "gen-sampled-from only returns values from the given set"
  (with-connection ()
    (let ((result (run-property "sampled from"
                   (lambda ()
                     (let ((x (generate (gen-sampled-from "apple" "banana" "cherry"))))
                       (assert (member x '("apple" "banana" "cherry") :test #'string=))))
                   :test-cases 30)))
      (is (test-result-passed result)))))

(test gen-list-returns-sequences
  "gen-list generates sequences of the element type"
  (with-connection ()
    (let ((result (run-property "list of integers"
                   (lambda ()
                     (let ((xs (generate (gen-list (gen-integer :min-value 0 :max-value 100)
                                                   :min-size 1 :max-size 5))))
                       (assert (typep xs 'sequence))
                       (assert (<= 1 (length xs) 5))
                       (assert (every #'integerp xs))))
                   :test-cases 30)))
      (is (test-result-passed result)))))

(test gen-one-of-returns-matching-type
  "gen-one-of generates values from one of the given schemas"
  (with-connection ()
    (let ((result (run-property "one of int or string"
                   (lambda ()
                     (let ((x (generate (gen-one-of (gen-integer) (gen-string)))))
                       (assert (or (integerp x) (stringp x)))))
                   :test-cases 30)))
      (is (test-result-passed result)))))

;;; Nested generators

(test nested-list-of-one-of
  "gen-list of gen-one-of composes correctly"
  (with-connection ()
    (let ((result (run-property "list of mixed"
                   (lambda ()
                     (let ((xs (generate (gen-list
                                          (gen-one-of (gen-integer :min-value 0)
                                                      (gen-constant "x"))
                                          :max-size 10))))
                       (assert (typep xs 'sequence))
                       (assert (every (lambda (x) (or (integerp x) (string= x "x"))) xs))))
                   :test-cases 20)))
      (is (test-result-passed result)))))

;;; Shrinking

(test shrinking-replays-run
  "Failing property triggers replays and signals property-failed with seed"
  (with-connection ()
    (let ((replay-count 0))
      (handler-case
          (progn
            (run-property "shrink test"
              (lambda ()
                (incf replay-count)
                (let ((x (generate (gen-integer :min-value 0 :max-value 100))))
                  (assert (< x 50))))
              :test-cases 20)
            (fail "Expected property-failed"))
        (property-failed (c)
          ;; Replays happened (body called more times than test_cases)
          (is (> replay-count 20))
          ;; Seed is captured for reproducibility
          (is (stringp (property-failed-seed c))))))))

;;; Seed replay

(test seed-reproduces-failure
  "Passing :seed to run-property reproduces the same failure"
  (with-connection ()
    (let ((captured-seed nil)
          (first-values nil)
          (second-values nil))
      ;; First run: capture the seed and failing values
      (handler-case
          (progn
            (run-property "seed replay test"
              (lambda ()
                (let ((x (generate (gen-integer :min-value -100 :max-value 100))))
                  (push x first-values)
                  (assert (>= x 0))))
              :test-cases 50)
            (fail "Expected property-failed"))
        (property-failed (c)
          (setf captured-seed (property-failed-seed c))))
      ;; Second run: same seed should fail again
      (handler-case
          (progn
            (run-property "seed replay test 2"
              (lambda ()
                (let ((x (generate (gen-integer :min-value -100 :max-value 100))))
                  (push x second-values)
                  (assert (>= x 0))))
              :test-cases 50
              :seed captured-seed)
            (fail "Expected property-failed on replay"))
        (property-failed (c)
          (is (string= captured-seed (property-failed-seed c))))))))

;;; Assume filtering

(test assume-filters-end-to-end
  "assume properly filters test cases through the protocol"
  (with-connection ()
    (let ((result (run-property "even only"
                   (lambda ()
                     (let ((x (generate (gen-integer :min-value 0 :max-value 100))))
                       (assume (evenp x))
                       (assert (evenp x))))
                   :test-cases 30)))
      (is (test-result-passed result))
      (is (plusp (test-result-valid-test-cases result))))))
