(defpackage #:hegel.rove
  (:use :cl :rove))

(in-package #:hegel.rove)

(defun maybe-generator-symbol (sym)
  "Get the actual generator symbol or the original symbol"
  (let ((sname (symbol-name sym))
        (pkg (find-package :hegel.generators)))
    (multiple-value-bind (gen-sym accessibility)
        (find-symbol sname pkg)
      (if (eq accessibility :external) gen-sym sym))))

(defun to-generator-symbols (form)
  (cond
    ((consp form)
     (mapcar #'to-generator-symbols form))
    ((symbolp form)
     (maybe-generator-symbol form))
    (t form)))

(defun wrap-generator (gen-list)
  (let* ((var-name (first gen-list))
         (gen-chain (to-generator-symbols (second gen-list))))
    `(,var-name (hegel:generate ,gen-chain))))

(defmacro property (name gen-list &body body)
  (let* ((generators (mapcar #'wrap-generator gen-list)))
    `(testing ,name
       (hegel:run-property ,name
          (lambda ()
             (let* ,generators
               ,@body))))))

(defun wrong-add (a b)
  (if (= a 2)
      (+ b 1)
      (+ a b)))
  
(deftest something
  (property "Adding is the same" ((a (integers))
                                  (b (integers)))
    (assert (= (wrong-add a b) (+ a b)))))
