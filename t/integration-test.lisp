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
      (is (test-result-passed result))
      (is (= 10 (test-result-test-cases result))))))

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
    (let ((result (run-property "multi-type generation"
                   (lambda ()
                     (let ((i (generate (gen-integer :min-value 0 :max-value 10)))
                           (b (generate (gen-boolean)))
                           (s (generate (gen-string :max-size 5))))
                       (assert (typep i 'integer))
                       (assert (typep b 'boolean))
                       (assert (typep s 'string))))
                   :test-cases 10)))
      (is (test-result-passed result)))))
