(in-package #:hegel/tests)

(def-suite runner-suite
  :description "Test runner tests"
  :in hegel-suite)

(in-suite runner-suite)

;;; Helpers to build mock server response packets

(defun make-cbor-payload (data)
  (let ((cbor:*use-stringrefs* nil)
        (cbor:*use-sharedrefs* nil))
    (coerce (cbor:encode data)
            '(simple-array (unsigned-byte 8) (*)))))

(defun make-cbor-packet (stream-id message-id data)
  (let ((payload (make-cbor-payload data)))
    (make-packet :stream-id stream-id
                 :message-id message-id
                 :payload-length (length payload)
                 :payload payload)))

(defconstant +mock-run-stream+ #x80000003
  "The run stream ID that run-property will allocate (first next-stream-id: (1<<1)|1 | bit31).")

(defun build-passing-responses (generated-value)
  "Build mock server responses for a 1-test-case passing run.
Per-stream msg-ids: control stream 1=run_test; tc stream 1=generate, 2=mark_complete."
  (list
   ;; 1. run_test_reply (control stream, reply to msg 1)
   (make-cbor-packet 0 (make-reply-id 1) t)
   ;; 2. test_case event on run stream, CBOR stream_id=2 for commands
   (make-cbor-packet +mock-run-stream+ 0
                     (alist-to-hash-table
                      `(("event" . "test_case")
                        ("stream_id" . 2)
                        ("is_final" . nil))))
   ;; 3. generate_reply (tc stream 2, reply to msg 1)
   (make-cbor-packet 2 (make-reply-id 1)
                     (alist-to-hash-table
                      `(("result" . ,generated-value))))
   ;; 4. mark_complete_reply (tc stream 2, reply to msg 2)
   (make-cbor-packet 2 (make-reply-id 2)
                     (alist-to-hash-table '(("result" . nil))))
   ;; 5. test_done event on run stream
   (make-cbor-packet +mock-run-stream+ 1
                     (alist-to-hash-table
                      '(("event" . "test_done")
                        ("results" . (("passed" . t)
                                      ("test_cases" . 1)
                                      ("valid_test_cases" . 1)
                                      ("invalid_test_cases" . 0)
                                      ("interesting_test_cases" . 0)
                                      ("seed" . "42"))))))))

(defun build-failing-responses (generated-value)
  "Build mock server responses for a 1-test-case failing run.
Per-stream msg-ids: control 1=run_test; tc-stream-2 1=gen,2=mark; tc-stream-4 1=gen,2=mark."
  (list
   ;; 1. run_test_reply (control stream, reply to msg 1)
   (make-cbor-packet 0 (make-reply-id 1) t)
   ;; 2. test_case event on run stream, CBOR stream_id=2
   (make-cbor-packet +mock-run-stream+ 0
                     (alist-to-hash-table
                      `(("event" . "test_case")
                        ("stream_id" . 2)
                        ("is_final" . nil))))
   ;; 3. generate_reply (tc stream 2, reply to msg 1)
   (make-cbor-packet 2 (make-reply-id 1)
                     (alist-to-hash-table
                      `(("result" . ,generated-value))))
   ;; 4. mark_complete_reply (tc stream 2, reply to msg 2)
   (make-cbor-packet 2 (make-reply-id 2)
                     (alist-to-hash-table '(("result" . nil))))
   ;; 5. test_done event on run stream
   (make-cbor-packet +mock-run-stream+ 1
                     (alist-to-hash-table
                      '(("event" . "test_done")
                        ("results" . (("passed" . nil)
                                      ("test_cases" . 1)
                                      ("valid_test_cases" . 0)
                                      ("invalid_test_cases" . 0)
                                      ("interesting_test_cases" . 1)
                                      ("seed" . "99"))))))
   ;; 6. Final replay: test_case on run stream, CBOR stream_id=4
   (make-cbor-packet +mock-run-stream+ 2
                     (alist-to-hash-table
                      `(("event" . "test_case")
                        ("stream_id" . 4)
                        ("is_final" . t))))
   ;; 7. generate_reply for replay (tc stream 4, reply to msg 1)
   (make-cbor-packet 4 (make-reply-id 1)
                     (alist-to-hash-table
                      `(("result" . ,generated-value))))
   ;; 8. mark_complete_reply for replay (tc stream 4, reply to msg 2)
   (make-cbor-packet 4 (make-reply-id 2)
                     (alist-to-hash-table '(("result" . nil))))))

;;; Tests

(test run-property-passing
  "A property that always passes returns a successful test-result"
  (let* ((conn (make-mock-connection (build-passing-responses 42))))
    (setf (hegel::connection-handshake-done-p conn) t)
    (let ((hegel:*connection* conn)
          (captured nil))
      (let ((result (run-property "always passes"
                      (lambda ()
                        (push (generate (gen-integer)) captured))
                      :test-cases 1)))
        (is (test-result-passed result))
        (is (= 1 (test-result-test-cases result)))
        (is (equal '(42) captured))))))

(test run-property-failing-signals-condition
  "A failing property signals property-failed with counterexample"
  (let* ((conn (make-mock-connection (build-failing-responses -1))))
    (setf (hegel::connection-handshake-done-p conn) t)
    (let ((hegel:*connection* conn))
      (handler-case
          (progn
            (run-property "always fails"
              (lambda ()
                (let ((x (generate (gen-integer))))
                  (when (< x 0)
                    (error "negative: ~A" x))))
              :test-cases 1)
            (fail "Expected property-failed to be signaled"))
        (property-failed (c)
          (is (string= "always fails" (property-failed-name c)))
          (is (string= "99" (property-failed-seed c))))))))

(test assume-skips-invalid-test-cases
  "assume signals invalid-test-case which the runner catches"
  (let* ((conn (make-mock-connection (build-passing-responses 42))))
    (setf (hegel::connection-handshake-done-p conn) t)
    (let ((hegel:*connection* conn))
      ;; assume with true should not skip
      (let ((result (run-property "assume true"
                      (lambda ()
                        (let ((x (generate (gen-integer))))
                          (assume (numberp x))))
                      :test-cases 1)))
        (is (test-result-passed result))))))
