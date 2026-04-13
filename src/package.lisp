(defpackage #:hegel
  (:use #:cl #:lisp-binary)
  (:export
   ;; Packet layer
   #:make-reply-id
   #:reply-p
   #:make-client-stream-id
   #:compute-checksum
   #:write-hegel-packet
   #:read-hegel-packet
   ;; Packet struct accessors
   #:packet
   #:make-packet
   #:packet-checksum
   #:packet-stream-id
   #:packet-message-id
   #:packet-payload-length
   #:packet-payload
   ;; Connection
   #:connection
   #:make-connection-from-streams
   #:start-hegel-core
   #:close-connection
   #:with-connection
   #:ensure-connection
   #:connection-input
   #:connection-output
   #:connection-handshake-done-p
   #:next-message-id
   #:next-stream-id
   #:perform-handshake
   ;; Protocol
   #:send-command
   #:send-stream-close
   #:read-message
   #:wait-for-reply
   #:alist-to-hash-table
   ;; Conditions and results
   #:property-failed
   #:property-failed-name
   #:property-failed-counterexample
   #:property-failed-seed
   #:property-failed-test-cases-run
   #:invalid-test-case
   #:hegel-connection-error
   #:hegel-connection-error-message
   #:test-result
   #:make-test-result
   #:test-result-passed
   #:test-result-test-cases
   #:test-result-valid-test-cases
   #:test-result-invalid-test-cases
   #:test-result-interesting-test-cases
   #:test-result-seed
   #:test-result-counterexample
   #:test-result-error
   ;; Runner
   #:*connection*
   #:run-property
   #:generate
   #:assume
   ;; Protocol (additional)
   #:*protocol-debug*
   #:send-reply
   #:encode-cbor
   #:decode-cbor
   ;; Generators
   #:gen-integer
   #:gen-boolean
   #:gen-string
   #:gen-list
   #:gen-one-of
   #:gen-constant
   #:gen-sampled-from))

(in-package #:hegel)
