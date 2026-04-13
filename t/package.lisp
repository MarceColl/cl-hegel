(defpackage #:hegel/tests
  (:use #:cl #:fiveam #:hegel)
  (:shadowing-import-from #:hegel #:gen-integer #:gen-list #:gen-string))

(in-package #:hegel/tests)

(def-suite hegel-suite
  :description "Tests for cl-hegel")

(def-suite packet-suite
  :description "Packet wire format tests"
  :in hegel-suite)
