(defpackage #:hegel/tests
  (:use #:cl #:fiveam #:hegel)
  (:shadowing-import-from #:hegel #:gen-integer #:gen-list #:gen-string)
  (:import-from #:hegel
    ;; Packet internals
    #:make-packet #:packet-checksum #:packet-stream-id #:packet-message-id
    #:packet-payload-length #:packet-payload
    #:write-hegel-packet #:read-hegel-packet
    #:make-reply-id #:reply-p #:make-client-stream-id
    #:compute-checksum
    ;; Connection internals
    #:make-connection-from-streams #:connection-output
    #:next-message-id #:next-stream-id
    #:perform-handshake #:connection-handshake-done-p
    #:start-hegel-core
    ;; Protocol internals
    #:send-command #:send-stream-close #:read-message
    #:alist-to-hash-table
    ;; Result constructor (for tests)
    #:make-test-result))

(in-package #:hegel/tests)

(def-suite hegel-suite
  :description "Tests for cl-hegel")
