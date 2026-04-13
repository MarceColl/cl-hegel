(defpackage #:hegel
  (:use #:cl #:lisp-binary)
  (:export
   ;; Runner
   #:*connection*
   #:run-property
   #:generate
   #:assume
   ;; Connection
   #:with-connection
   #:close-connection
   ;; Generators
   #:gen-integer
   #:gen-boolean
   #:gen-string
   #:gen-list
   #:gen-one-of
   #:gen-constant
   #:gen-sampled-from
   ;; Conditions
   #:property-failed
   #:property-failed-name
   #:property-failed-counterexample
   #:property-failed-seed
   #:property-failed-test-cases-run
   #:invalid-test-case
   ;; Results
   #:test-result
   #:test-result-passed
   #:test-result-test-cases
   #:test-result-valid-test-cases
   #:test-result-invalid-test-cases
   #:test-result-interesting-test-cases
   #:test-result-seed
   #:test-result-counterexample
   #:test-result-error
   ;; Debug
   #:*protocol-debug*))

(in-package #:hegel)
