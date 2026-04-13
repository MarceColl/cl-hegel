(in-package #:hegel/tests)

(def-suite protocol-suite
  :description "Protocol layer tests"
  :in hegel-suite)

(in-suite protocol-suite)

;;; Helper to build a mock connection with pre-loaded server responses

(defun make-mock-connection (&optional response-packets)
  "Create a connection where the server-to-client stream has RESPONSE-PACKETS pre-loaded."
  (let* ((client-out (flexi-streams:make-in-memory-output-stream
                      :element-type '(unsigned-byte 8)))
         (server-bytes
           (if response-packets
               (flexi-streams:with-output-to-sequence (tmp :element-type '(unsigned-byte 8))
                 (dolist (pkt response-packets)
                   (write-hegel-packet tmp pkt)))
               (make-array 0 :element-type '(unsigned-byte 8))))
         (server-in (flexi-streams:make-in-memory-input-stream server-bytes)))
    (make-connection-from-streams client-out server-in)))

;;; alist-to-hash-table

(test alist-to-hash-table-basic
  (let ((ht (alist-to-hash-table '(("command" . "generate") ("value" . 42)))))
    (is (string= "generate" (gethash "command" ht)))
    (is (= 42 (gethash "value" ht)))))

;;; send-command encodes CBOR and sends a packet

(test send-command-sends-cbor-packet
  (let* ((reply-payload (coerce (cbor:encode t)
                                '(simple-array (unsigned-byte 8) (*))))
         (reply-pkt (make-packet :stream-id 0
                                 :message-id (make-reply-id 1)
                                 :payload-length (length reply-payload)
                                 :payload reply-payload))
         (conn (make-mock-connection (list reply-pkt)))
         (result (send-command conn 0 '(("command" . "run_test")
                                        ("test_cases" . 100)))))
    ;; Should return the decoded reply
    (is (eq t result))
    ;; Verify the sent packet has CBOR-encoded payload
    (let* ((sent-bytes (flexi-streams:get-output-stream-sequence
                        (connection-output conn)))
           (sent-pkt (flexi-streams:with-input-from-sequence (in sent-bytes)
                       (read-hegel-packet in)))
           (cbor:*dictionary-format* :alist)
           (decoded (cbor:decode (packet-payload sent-pkt))))
      (is (string= "run_test" (cdr (assoc "command" decoded :test #'string=))))
      (is (= 100 (cdr (assoc "test_cases" decoded :test #'string=)))))))

;;; send-stream-close sends raw 0xFE payload

(test send-stream-close-sends-fe-byte
  (let* ((conn (make-mock-connection))
         (stream-id 42))
    (send-stream-close conn stream-id)
    (let* ((sent-bytes (flexi-streams:get-output-stream-sequence
                        (connection-output conn)))
           (sent-pkt (flexi-streams:with-input-from-sequence (in sent-bytes)
                       (read-hegel-packet in))))
      (is (= 42 (packet-stream-id sent-pkt)))
      ;; Message ID = (1 << 31) - 1
      (is (= #x7FFFFFFF (packet-message-id sent-pkt)))
      ;; Payload is single byte 0xFE
      (is (= 1 (packet-payload-length sent-pkt)))
      (is (= #xFE (aref (packet-payload sent-pkt) 0))))))

;;; read-message decodes CBOR from incoming packet

(test read-message-decodes-cbor
  (let* ((cbor-payload (cbor:encode
                        (alist-to-hash-table '(("event" . "test_case")
                                               ("stream_id" . 5)
                                               ("is_final" . nil)))))
         (server-pkt (make-packet :stream-id 0
                                  :message-id 0
                                  :payload-length (length cbor-payload)
                                  :payload (coerce cbor-payload
                                                   '(simple-array (unsigned-byte 8) (*)))))
         (conn (make-mock-connection (list server-pkt)))
         (msg (read-message conn)))
    (is (string= "test_case" (cdr (assoc "event" msg :test #'string=))))
    (is (= 5 (cdr (assoc "stream_id" msg :test #'string=))))))
