(in-package #:hegel/tests)

(def-suite conditions-suite
  :description "Conditions and result struct tests"
  :in hegel-suite)

(in-suite conditions-suite)

;;; property-failed condition

(test property-failed-is-an-error
  (is (typep (make-condition 'property-failed
                             :name "my-test"
                             :counterexample '(42)
                             :seed "12345"
                             :test-cases-run 10)
             'error)))

(test property-failed-slots
  (let ((c (make-condition 'property-failed
                           :name "sort test"
                           :counterexample '((3 1 2))
                           :seed "99"
                           :test-cases-run 5)))
    (is (string= "sort test" (property-failed-name c)))
    (is (equal '((3 1 2)) (property-failed-counterexample c)))
    (is (string= "99" (property-failed-seed c)))
    (is (= 5 (property-failed-test-cases-run c)))))

;;; invalid-test-case condition

(test invalid-test-case-is-a-condition
  (is (typep (make-condition 'invalid-test-case) 'condition))
  ;; It should NOT be an error - it's a control flow mechanism
  (is (not (typep (make-condition 'invalid-test-case) 'error))))

;;; test-result struct

(test test-result-struct
  (let ((r (make-test-result :passed t
                             :test-cases 100
                             :valid-test-cases 95
                             :invalid-test-cases 5
                             :interesting-test-cases 0
                             :seed "42"
                             :counterexample nil
                             :error nil)))
    (is (test-result-passed r))
    (is (= 100 (test-result-test-cases r)))
    (is (= 95 (test-result-valid-test-cases r)))
    (is (= 5 (test-result-invalid-test-cases r)))
    (is (= 0 (test-result-interesting-test-cases r)))
    (is (string= "42" (test-result-seed r)))
    (is (null (test-result-counterexample r)))
    (is (null (test-result-error r)))))
