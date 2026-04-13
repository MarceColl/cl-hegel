(in-package #:hegel)

(define-condition property-failed (error)
  ((name :initarg :name :reader property-failed-name)
   (counterexample :initarg :counterexample :initform nil :reader property-failed-counterexample)
   (seed :initarg :seed :reader property-failed-seed)
   (test-cases-run :initarg :test-cases-run :reader property-failed-test-cases-run))
  (:report (lambda (c stream)
             (format stream "Property ~S failed after ~D test cases.~%Seed: ~A~%Counterexample: ~S"
                     (property-failed-name c)
                     (property-failed-test-cases-run c)
                     (property-failed-seed c)
                     (property-failed-counterexample c)))))

(define-condition invalid-test-case (condition)
  ())

(define-condition test-aborted (condition)
  ())


(defstruct test-result
  (passed nil :type boolean)
  (test-cases 0 :type integer)
  (valid-test-cases 0 :type integer)
  (invalid-test-cases 0 :type integer)
  (interesting-test-cases 0 :type integer)
  (seed "" :type string)
  (counterexample nil)
  (error nil))
